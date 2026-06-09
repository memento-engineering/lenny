import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show
        PluginManifestEntry,
        SessionEnded,
        SessionOutcome,
        SessionProgressEvent,
        SessionStarted,
        SessionTermination,
        TrajectoryRecord,
        capabilitiesFor;
import 'package:flutter/material.dart';

import '../conversation/conversation_state.dart' show RunStatus;
import 'model_catalog.dart';
import 'prompt_panel.dart';
import 'prompt_panel_config.dart';
import 'prompt_panel_config_store.dart';
import 'prompt_panel_controller.dart';
import 'provider_config.dart';
import 'provider_config_store.dart';

/// Mounts the [PromptPanel] into [ExplorationShell]'s Prompt tab.
///
/// Owns:
///   - a [PromptPanelController] for the panel's lifecycle, and
///   - a [ValueNotifier]<[ModelCatalogState]> that drives the model
///     dropdown. Provider config edits persist via [store] and then
///     trigger a fetch through the shared [ModelCatalog].
class PromptTabMount extends StatefulWidget {
  const PromptTabMount({
    super.key,
    required this.plugins,
    required this.store,
    required this.catalog,
    required this.controllerFactory,
    required this.promptConfigStore,
    this.trajectorySink,
    this.completionSink,
    this.initialProviderId = 'swift-infer',
  });

  /// Plugin manifest from the binding handshake.
  final List<PluginManifestEntry> plugins;

  /// Per-provider config persistence.
  final ProviderConfigStore store;

  /// Shared model catalog (panel + form share its cache).
  final ModelCatalog catalog;

  /// Optional write-side seam — when non-null, [_ensureController]
  /// assigns the controller's live trajectory stream to this notifier
  /// so the Timeline tab can render records emitted during the run.
  final ValueNotifier<Stream<TrajectoryRecord>?>? trajectorySink;

  /// When set, written with the terminal [RunStatus] when the run future
  /// resolves (done / error) or the user presses Stop (stopped).
  final ValueNotifier<RunStatus?>? completionSink;

  /// Provider id loaded from [store] at mount. Defaults to
  /// `'swift-infer'`.
  final String initialProviderId;

  /// Persists and restores last-used form state across reloads.
  final PromptPanelConfigStore promptConfigStore;

  /// Builds the [PromptPanelController] for this mount. The shell wires
  /// `() => PromptPanelController(factory: <closure over serviceManager>)`;
  /// tests inject a fake.
  final PromptPanelController Function() controllerFactory;

  @override
  State<PromptTabMount> createState() => _PromptTabMountState();
}

class _PromptTabMountState extends State<PromptTabMount> {
  PromptPanelController? _controller;
  StreamSubscription<SessionProgressEvent>? _sub;
  bool _running = false;
  bool _stoppedByUser = false;

  final ValueNotifier<ModelCatalogState> _state =
      ValueNotifier<ModelCatalogState>(const ModelCatalogState());
  String _conversationId = '';
  PromptPanelConfig? _initialPromptConfig;
  bool _configLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final loaded = await widget.store.load(widget.initialProviderId);
    if (loaded != null) {
      if (!mounted) return;
      _state.value = _state.value.copyWith(config: loaded);
      await _refresh(reload: false);
    }
    if (!mounted) return;
    final liveNamespaces = widget.plugins.map((p) => p.namespace).toSet();
    final promptCfg = await widget.promptConfigStore.load(
      liveNamespaces: liveNamespaces,
    );
    if (!mounted) return;
    setState(() {
      _configLoaded = true;
      if (promptCfg != null) _initialPromptConfig = promptCfg;
    });
  }

  Future<void> _refresh({required bool reload}) async {
    final cfg = _state.value.config;
    if (cfg == null) return;
    _state.value = _state.value.copyWith(loading: true, clearError: true);
    try {
      final models = await widget.catalog.fetch(
        cfg,
        reload: reload,
        conversationId: _conversationId,
      );
      if (!mounted) return;
      _state.value = _state.value.copyWith(
        models: models,
        loading: false,
        clearError: true,
      );
    } on Object catch (e) {
      if (!mounted) return;
      _state.value = _state.value.copyWith(loading: false, error: e);
    }
  }

  void _onProviderConfigChanged(ProviderConfig cfg) {
    _state.value = _state.value.copyWith(config: cfg);
    unawaited(widget.store.save(cfg));
    unawaited(_refresh(reload: true));
  }

  PromptPanelController _ensureController() {
    final existing = _controller;
    if (existing != null) return existing;
    final c = widget.controllerFactory();
    // Surface the controller's live trajectory to the Timeline tab.
    widget.trajectorySink?.value = c.trajectory;
    _sub = c.events.listen((event) {
      if (!mounted) return;
      if (event is SessionStarted) {
        setState(() {
          _running = true;
          _conversationId =
              'exploration-${DateTime.now().millisecondsSinceEpoch}';
        });
      } else if (event is SessionEnded) {
        setState(() => _running = false);
      }
    });
    _controller = c;
    return c;
  }

  RunStatus _termToRunStatus(SessionTermination t) {
    if (_stoppedByUser) return RunStatus.stopped;
    return switch (t.outcome) {
      SessionOutcome.done => RunStatus.done,
      SessionOutcome.budgetExhausted => RunStatus.done,
      SessionOutcome.harnessError => RunStatus.error,
    };
  }

  Future<void> _onStart(PromptPanelConfig cfg) async {
    // Persist before starting so the config survives even if start fails.
    unawaited(widget.promptConfigStore.save(
      cfg,
      knownNamespaces: widget.plugins.map((p) => p.namespace).toSet(),
    ));
    _stoppedByUser = false;
    final c = _ensureController();
    await c.start(cfg, providerCfg: _state.value.config);
    // Re-enable the form when the loop terminates naturally (vs.
    // user pressing Stop). LoopDriver's finally block closes the
    // writer; we also need to flip _running back so the UI restores
    // the Start button. We use then().whenComplete() so we can signal
    // the completionSink with the terminal status before tearing down.
    unawaited(c.runFuture?.then((t) {
      if (!mounted) return;
      widget.completionSink?.value = _termToRunStatus(t);
    }).whenComplete(() {
      if (!mounted) return;
      unawaited(c.stop());
    }));
  }

  Future<void> _onStop() async {
    _stoppedByUser = true;
    await _controller?.stop();
  }

  /// Installs a synthetic single-entry catalog state so the dropdown
  /// becomes selectable when the live `/v1/models` fetch is dead. The
  /// banner is cleared deliberately — the user has acknowledged the
  /// failure and chosen recovery; leaving the banner alongside a
  /// working dropdown would be confusing. Pressing the reload button
  /// re-runs the live fetch (and the banner re-fires if it still fails).
  void _onUseFallback(String modelId) {
    final cfg = _state.value.config;
    _state.value = ModelCatalogState(
      config: cfg,
      models: <ResolvedModel>[
        ResolvedModel(
          id: modelId,
          label: modelId,
          capabilities:
              cfg == null ? null : capabilitiesFor(cfg.id, modelId),
          usingFallback: true,
        ),
      ],
      loading: false,
      // error intentionally cleared.
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller?.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ModelCatalogState>(
        valueListenable: _state,
        builder: (context, state, _) => PromptPanel(
          modelsState: state,
          plugins: widget.plugins,
          running: _running,
          onStart: _onStart,
          onStop: _onStop,
          onProviderConfigChanged: _onProviderConfigChanged,
          onReloadModels: () => unawaited(_refresh(reload: true)),
          catalog: widget.catalog,
          conversationId: _conversationId,
          onUseFallback: _onUseFallback,
          initialConfig: _initialPromptConfig,
          configLoaded: _configLoaded,
        ),
      );
}
