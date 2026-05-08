import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show
        PluginManifestEntry,
        SessionEnded,
        SessionProgressEvent,
        SessionStarted;
import 'package:flutter/material.dart';

import '../panel_host.dart';
import 'prompt_panel.dart';
import 'prompt_panel_config.dart';
import 'prompt_panel_controller.dart';

/// Mounts the [PromptPanel] into [ExplorationShell]'s Prompt tab.
///
/// Owns a [PromptPanelController] for the panel's lifecycle. Resolves the
/// VM service URI through the [ExplorationPanelHost.of] ancestor's
/// [VmServiceUriResolver] so the panel works with the same DTD wiring as
/// the timeline tab.
///
/// Models / plugin manifest are passed in by the host. cx6.14/.15/.16 and
/// cx6.11 will populate them via dependency injection from the shell;
/// for now the shell forwards static defaults.
class PromptTabMount extends StatefulWidget {
  const PromptTabMount({
    super.key,
    required this.availableModels,
    required this.plugins,
    this.controllerFactory,
  });

  final List<ModelDescriptor> availableModels;
  final List<PluginManifestEntry> plugins;

  /// Test seam — production builds a real [PromptPanelController] keyed
  /// to the host's resolved VM service URI.
  final PromptPanelController Function(Uri vmServiceUri)? controllerFactory;

  @override
  State<PromptTabMount> createState() => _PromptTabMountState();
}

class _PromptTabMountState extends State<PromptTabMount> {
  PromptPanelController? _controller;
  StreamSubscription<SessionProgressEvent>? _sub;
  bool _running = false;

  PromptPanelController _ensureController(Uri uri) {
    final existing = _controller;
    if (existing != null) return existing;
    final c = widget.controllerFactory != null
        ? widget.controllerFactory!(uri)
        : PromptPanelController(vmServiceUri: uri);
    _sub = c.events.listen((event) {
      if (!mounted) return;
      if (event is SessionStarted) {
        setState(() => _running = true);
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
    await c.start(cfg);
  }

  Future<void> _onStop() async {
    await _controller?.stop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PromptPanel(
        availableModels: widget.availableModels,
        plugins: widget.plugins,
        running: _running,
        onStart: _onStart,
        onStop: _onStop,
      );
}
