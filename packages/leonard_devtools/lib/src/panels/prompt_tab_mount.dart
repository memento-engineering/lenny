import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart'
    show
        ExtensionManifestEntry,
        SessionEnded,
        SessionOutcome,
        SessionProgressEvent,
        SessionStarted,
        SessionTermination,
        TrajectoryRecord,
        capabilitiesFor;
import 'package:flutter/material.dart';

import '../conversation/conversation_state.dart' show RunStatus;
import '../dtd_acp_model_provider.dart';
import 'model_catalog.dart';
import 'prompt_panel.dart';
import 'prompt_panel_config.dart';
import 'prompt_panel_config_store.dart';
import 'prompt_panel_controller.dart';
import 'provider_config.dart';
import 'provider_config_store.dart';

/// Mounts the [PromptPanel] into [LeonardShell]'s Prompt tab.
///
/// Owns:
///   - a [PromptPanelController] for the panel's lifecycle, and
///   - a [ValueNotifier]<[ModelCatalogState]> that drives the model
///     dropdown. Provider config edits persist via [store] and then
///     trigger a fetch through the shared [ModelCatalog].
class PromptTabMount extends StatefulWidget {
  PromptTabMount({
    super.key,
    required this.extensions,
    required this.store,
    required this.catalog,
    required this.controllerFactory,
    required this.promptConfigStore,
    this.trajectorySink,
    this.completionSink,
    this.sessionGenerationSink,
    this.initialProviderId = 'swift-infer',
    DtdAcpPanelClient? acpPanelClient,
  }) : acpPanelClient = acpPanelClient ?? DtdAcpPanelClient.unavailable();

  /// Extension manifest from the binding handshake.
  final List<ExtensionManifestEntry> extensions;

  /// Per-provider config persistence.
  final ProviderConfigStore store;

  /// Shared model catalog (panel + form share its cache).
  final ModelCatalog catalog;

  /// Web-safe client for ACP discovery, models, and provider construction.
  final DtdAcpPanelClient acpPanelClient;

  /// Optional write-side seam — when non-null, [_ensureController]
  /// assigns the controller's live trajectory stream to this notifier
  /// so the Timeline tab can render records emitted during the run.
  final ValueNotifier<Stream<TrajectoryRecord>?>? trajectorySink;

  /// When set, written with the terminal [RunStatus] when the run future
  /// resolves (done / error) or the user presses Stop (stopped).
  final ValueNotifier<RunStatus?>? completionSink;

  /// Resident monotonic counter advanced by the existing session-event
  /// subscription whenever it observes [SessionStarted].
  final ValueNotifier<int>? sessionGenerationSink;

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
  List<String> _acpHarnessLabels = const <String>[];
  int _refreshGeneration = 0;

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
    }
    if (loaded is AcpUiConfig) {
      await _refresh(reload: false);
    } else {
      try {
        await _discoverAcpHost();
      } on Object {
        // ACP discovery is optional while another provider is selected.
      }
      if (loaded != null) await _refresh(reload: false);
    }
    if (!mounted) return;
    final liveNamespaces = widget.extensions.map((p) => p.namespace).toSet();
    final promptCfg = await widget.promptConfigStore.load(
      liveNamespaces: liveNamespaces,
    );
    if (!mounted) return;
    setState(() {
      _configLoaded = true;
      if (promptCfg != null) _initialPromptConfig = promptCfg;
    });
  }

  Future<DtdAcpHostInfo?> _discoverAcpHost() async {
    try {
      final DtdAcpHostInfo? host = await widget.acpPanelClient.refreshHost();
      if (!mounted) return host;
      setState(
        () => _acpHarnessLabels = host?.harnessLabels ?? const <String>[],
      );
      return host;
    } on Object {
      if (mounted) setState(() => _acpHarnessLabels = const <String>[]);
      rethrow;
    }
  }

  Future<void> _refresh({required bool reload}) async {
    final cfg = _state.value.config;
    if (cfg == null) return;
    final int generation = ++_refreshGeneration;
    _state.value = _state.value.copyWith(loading: true, clearError: true);
    try {
      final List<ResolvedModel> models;
      ProviderConfig resolvedConfig = cfg;
      switch (cfg) {
        case HttpProviderConfig():
          models = await widget.catalog.fetch(
            cfg,
            reload: reload,
            conversationId: _conversationId,
          );
        case AcpUiConfig():
          final DtdAcpHostInfo? host = await _discoverAcpHost();
          if (host == null) {
            throw const DtdAcpUnavailable(
              'No ACP host is registered with the Dart Tooling Daemon.',
            );
          }
          final DtdAcpSessionModels session = await widget.acpPanelClient
              .newSession(harnessLabel: cfg.harnessLabel, modelId: cfg.modelId);
          if (session.availableModels.isEmpty) {
            throw StateError('ACP host returned no available models');
          }
          final String selected =
              session.currentModelId != null &&
                  session.availableModels.contains(session.currentModelId)
              ? session.currentModelId!
              : session.availableModels.first;
          final capabilities = DtdAcpModelProvider.decodeCapabilities(
            host.capabilities,
          );
          models = <ResolvedModel>[
            for (final String id in session.availableModels)
              ResolvedModel(id: id, label: id, capabilities: capabilities),
          ];
          resolvedConfig = cfg.copyWith(modelId: selected);
      }
      if (!mounted || generation != _refreshGeneration) return;
      if (resolvedConfig != cfg) {
        unawaited(widget.store.save(resolvedConfig));
      }
      _state.value = ModelCatalogState(
        config: resolvedConfig,
        models: models,
        loading: false,
      );
    } on Object catch (e) {
      if (!mounted || generation != _refreshGeneration) return;
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
    _sub = c.events.listen((event) {
      if (!mounted) return;
      if (event is SessionStarted) {
        widget.completionSink?.value = null;
        final generationSink = widget.sessionGenerationSink;
        if (generationSink != null) {
          generationSink.value = generationSink.value + 1;
        }
        setState(() {
          _running = true;
          _conversationId = 'leonard-${DateTime.now().millisecondsSinceEpoch}';
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
    unawaited(
      widget.promptConfigStore.save(
        cfg,
        knownNamespaces: widget.extensions.map((p) => p.namespace).toSet(),
      ),
    );
    _stoppedByUser = false;
    final c = _ensureController();
    await c.start(cfg, providerCfg: _state.value.config);
    if (!mounted) return;
    // Publish the controller's live trajectory ONLY after start(). start()
    // builds the BroadcastTrajectorySink (so `c.trajectory` is the live record
    // stream, not the pre-start `Stream.empty()` placeholder) and creates the
    // session via the host factory (so the shell's _onTrajectoryChanged finds a
    // non-null session and can build the ConversationViewModel that drives the
    // transcript + Timeline tab). Doing this pre-start in _ensureController is
    // why the transcript never populated: the shell's listener fired once with
    // an empty stream and a null session, then never again.
    widget.trajectorySink?.value = c.trajectory;
    // Re-enable the form when the loop terminates naturally (vs.
    // user pressing Stop). LoopDriver's finally block closes the
    // writer; we also need to flip _running back so the UI restores
    // the Start button. We use then().whenComplete() so we can signal
    // the completionSink with the terminal status before tearing down.
    unawaited(
      c.runFuture
          ?.then(
            (t) {
              if (!mounted) return;
              widget.completionSink?.value = _termToRunStatus(t);
            },
            // A run-level throw (e.g. the model/provider HTTP path — a
            // dartantic backend can throw on the request) MUST be handled
            // here. Without an onError the failed runFuture escapes the
            // surrounding `unawaited` as an unhandled async error, which
            // crashes the whole DevTools panel. Surface a terminal error
            // status; the whenComplete below still tears the session down
            // and re-enables the form. We deliberately do NOT log the
            // exception: a provider/HTTP error can embed request headers
            // (the api key), and this package is redaction-guarded against
            // print/debugPrint — diagnose model-path failures from the
            // browser Network tab instead.
            onError: (Object _, StackTrace __) {
              if (!mounted) return;
              widget.completionSink?.value = RunStatus.error;
            },
          )
          .whenComplete(() {
            if (!mounted) return;
            unawaited(c.stop());
          }),
    );
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
          capabilities: cfg == null ? null : capabilitiesFor(cfg.id, modelId),
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
          extensions: widget.extensions,
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
          acpHarnessLabels: _acpHarnessLabels,
        ),
      );
}
