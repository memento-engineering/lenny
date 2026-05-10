import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show
        PluginManifestEntry,
        SessionEnded,
        SessionProgressEvent,
        SessionStarted;
import 'package:flutter/material.dart';

import '../panel_host.dart';
import 'model_catalog.dart';
import 'prompt_panel.dart';
import 'prompt_panel_config.dart';
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
    this.controllerFactory,
    this.initialProviderId = 'swift-infer',
  });

  /// Plugin manifest from the binding handshake.
  final List<PluginManifestEntry> plugins;

  /// Per-provider config persistence.
  final ProviderConfigStore store;

  /// Shared model catalog (panel + form share its cache).
  final ModelCatalog catalog;

  /// Provider id loaded from [store] at mount. Defaults to
  /// `'swift-infer'`.
  final String initialProviderId;

  /// Test seam — production builds a real [PromptPanelController].
  final PromptPanelController Function(Uri vmServiceUri)? controllerFactory;

  @override
  State<PromptTabMount> createState() => _PromptTabMountState();
}

class _PromptTabMountState extends State<PromptTabMount> {
  PromptPanelController? _controller;
  StreamSubscription<SessionProgressEvent>? _sub;
  bool _running = false;

  final ValueNotifier<ModelCatalogState> _state =
      ValueNotifier<ModelCatalogState>(const ModelCatalogState());
  String _conversationId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final loaded = await widget.store.load(widget.initialProviderId);
    if (loaded == null) return;
    _state.value = _state.value.copyWith(config: loaded);
    await _refresh(reload: false);
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

  PromptPanelController _ensureController(Uri uri) {
    final existing = _controller;
    if (existing != null) return existing;
    final c = widget.controllerFactory != null
        ? widget.controllerFactory!(uri)
        : PromptPanelController(vmServiceUri: uri);
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

  Future<void> _onStart(PromptPanelConfig cfg) async {
    final host = ExplorationPanelHost.of(context);
    final raw = host.widget.vmServiceUri();
    if (raw == null) return;
    final c = _ensureController(Uri.parse(raw));
    await c.start(cfg, providerCfg: _state.value.config);
  }

  Future<void> _onStop() async {
    await _controller?.stop();
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
        ),
      );
}
