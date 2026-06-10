import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry;
import 'package:flutter/material.dart';

import 'model_catalog.dart';
import 'prompt_panel_config.dart';
import 'provider_config.dart';

/// Goal / model / budget / plugin form rendered into the DevTools
/// extension's Prompt tab. Stateless w.r.t. running session — owners
/// pass [running] in and react to [onStart] / [onStop] callbacks.
///
/// Consumes a [ModelCatalogState]: provider config form sits above the
/// model dropdown; the dropdown is populated from
/// [ModelCatalogState.models] with capability badges. Edits to the
/// provider config bubble up via [onProviderConfigChanged]; the
/// reload button (keyed `prompt.modelsReload`) fires
/// [onReloadModels].
class PromptPanel extends StatefulWidget {
  const PromptPanel({
    super.key,
    required this.modelsState,
    required this.plugins,
    required this.running,
    required this.onStart,
    required this.onStop,
    required this.onProviderConfigChanged,
    required this.onReloadModels,
    required this.catalog,
    this.conversationId = '',
    this.pluginGuideUrl =
        'https://example.com/exploration-agent/plugin-authoring',
    this.onUseFallback,
    this.initialConfig,
    this.configLoaded = false,
  });

  /// Snapshot of the model catalog (provider config + resolved
  /// models + loading/error state).
  final ModelCatalogState modelsState;

  /// Plugin manifest from the binding handshake. Empty list renders
  /// the empty-state guide hint instead of toggles.
  final List<PluginManifestEntry> plugins;

  /// `true` while a session is in flight.
  final bool running;

  /// Invoked when the user submits a valid form.
  final void Function(PromptPanelConfig) onStart;

  /// Invoked when the user presses Stop while [running] is true.
  final VoidCallback onStop;

  /// Bubbles provider config edits up to the mount layer (which
  /// persists + triggers a model-list refresh).
  final void Function(ProviderConfig) onProviderConfigChanged;

  /// Fires when the reload button is pressed.
  final VoidCallback onReloadModels;

  /// Shared catalog instance used by the form's "Test connection"
  /// button.
  final ModelCatalog catalog;

  /// Conversation id breadcrumb (swift-infer only). Empty string when
  /// no session has started yet.
  final String conversationId;

  /// URL surfaced in the empty-plugin hint.
  final String pluginGuideUrl;

  /// Invoked when the user taps the `Use fallback model: <id>` link in
  /// the error banner. Only rendered for [SwiftInferUiConfig] (the
  /// only provider with a documented "always-available" model id).
  /// `null` disables the link.
  final void Function(String modelId)? onUseFallback;

  /// Pre-fills the form from the last-used config. Null on first-ever load
  /// (form shows defaults). Applied in [State.initState] if already set, or in
  /// [State.didUpdateWidget] when the async bootstrap delivers it after mount.
  final PromptPanelConfig? initialConfig;

  /// True once the async config load in [PromptTabMount] completes.
  /// When this transitions false→true and [initialConfig] is null (no saved
  /// config), the settings section auto-opens so the user can enter their
  /// keys on first launch.
  final bool configLoaded;

  @override
  State<PromptPanel> createState() => _PromptPanelState();
}

class _PromptPanelState extends State<PromptPanel> {
  late final TextEditingController _goal = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _modelId;
  int _maxTurns = 50;
  Duration _budget = const Duration(minutes: 15);
  Set<String> _enabled = const <String>{};
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    final ic = widget.initialConfig;
    if (ic != null) {
      _goal.text = ic.goal;
      _maxTurns = ic.maxTurns;
      _budget = ic.wallClockBudget;
      _enabled = ic.enabledPluginNamespaces.toSet();
    } else {
      _enabled = widget.plugins.map((p) => p.namespace).toSet();
      if (widget.configLoaded) _settingsOpen = true;
    }
    _modelId = widget.modelsState.models.isNotEmpty
        ? widget.modelsState.models.first.id
        : null;
  }

  @override
  void didUpdateWidget(covariant PromptPanel old) {
    super.didUpdateWidget(old);
    if (old.initialConfig == null && widget.initialConfig != null) {
      final ic = widget.initialConfig!;
      setState(() {
        _goal.text = ic.goal;
        _maxTurns = ic.maxTurns;
        _budget = ic.wallClockBudget;
        _enabled = ic.enabledPluginNamespaces.toSet();
      });
    }
    if (!old.configLoaded &&
        widget.configLoaded &&
        widget.initialConfig == null) {
      setState(() => _settingsOpen = true);
    }
    final models = widget.modelsState.models;
    if (_modelId == null && models.isNotEmpty) {
      _modelId = models.first.id;
    } else if (_modelId != null && !models.any((m) => m.id == _modelId)) {
      _modelId = models.isNotEmpty ? models.first.id : null;
    }
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final id = _modelId;
    if (id == null) return;
    widget.onStart(
      PromptPanelConfig(
        goal: _goal.text,
        modelId: id,
        maxTurns: _maxTurns,
        wallClockBudget: _budget,
        enabledPluginNamespaces: _enabled,
      ),
    );
  }

  List<Widget> _badges(ResolvedModel m) {
    final out = <Widget>[];
    if (m.usingFallback) {
      out.add(const _Badge(text: 'using fallback', key: Key('badge.fallback')));
    }
    final c = m.capabilities;
    if (c == null) {
      out.add(
        const _Badge(text: '⚠ unknown capabilities', key: Key('badge.unknown')),
      );
      return out;
    }
    if (c.vision) out.add(const _Badge(text: 'vision'));
    if (c.preserveThinking) out.add(const _Badge(text: 'thinking'));
    return out;
  }

  Widget _buildSettingsSection(ModelCatalogState state, bool running) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ProviderConfigForm(
          initial: state.config,
          onChanged: widget.onProviderConfigChanged,
          conversationId: widget.conversationId,
          catalog: widget.catalog,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const Key('prompt.model'),
                initialValue: _modelId,
                items: state.models
                    .map(
                      (m) => DropdownMenuItem<String>(
                        value: m.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(m.label),
                            ..._badges(m).map(
                              (b) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: b,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: running
                    ? null
                    : (v) => setState(() => _modelId = v ?? _modelId),
              ),
            ),
            IconButton(
              key: const Key('prompt.modelsReload'),
              tooltip: 'Reload models',
              icon: state.loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: state.loading ? null : widget.onReloadModels,
            ),
          ],
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              key: const Key('prompt.modelsError'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                border: Border.all(color: Colors.red.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          state.error.toString(),
                          style: const TextStyle(color: Colors.black87),
                        ),
                        if (_fallbackModelIdFor(state.config) !=
                            null) ...<Widget>[
                          const SizedBox(height: 8),
                          InkWell(
                            key: const Key('prompt.modelsError.useFallback'),
                            onTap: widget.onUseFallback == null
                                ? null
                                : () => widget.onUseFallback!(
                                    _fallbackModelIdFor(state.config)!,
                                  ),
                            child: Text(
                              'Use fallback model: '
                              '${_fallbackModelIdFor(state.config)}',
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        TextFormField(
          key: const Key('prompt.maxTurns'),
          initialValue: '$_maxTurns',
          enabled: !running,
          decoration: const InputDecoration(labelText: 'Max turns'),
          onChanged: (v) => _maxTurns = int.tryParse(v) ?? _maxTurns,
        ),
        TextFormField(
          key: const Key('prompt.wallMinutes'),
          initialValue: '${_budget.inMinutes}',
          enabled: !running,
          decoration: const InputDecoration(
            labelText: 'Wall-clock budget (minutes)',
          ),
          onChanged: (v) => _budget = Duration(minutes: int.tryParse(v) ?? 15),
        ),
        if (widget.plugins.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No plugins registered. See ${widget.pluginGuideUrl}',
              key: const Key('prompt.pluginsEmpty'),
            ),
          )
        else
          ...widget.plugins.map(
            (p) => CheckboxListTile(
              key: Key('prompt.plugin.${p.namespace}'),
              title: Text(p.namespace),
              value: _enabled.contains(p.namespace),
              onChanged: running
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _enabled.add(p.namespace);
                      } else {
                        _enabled.remove(p.namespace);
                      }
                    }),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.running;
    final state = widget.modelsState;

    return Form(
      key: _formKey,
      // Column (not SingleChildScrollView) so the composer is a compact bar
      // sized to its content and pinned to the bottom of the shell. The
      // settings panel reveals on demand ABOVE the composer and is itself
      // bounded + scrollable, so opening it never blows out the layout.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildSettingsSection(state, running),
              ),
            ),
            crossFadeState: _settingsOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: const Key('prompt.goal'),
                      controller: _goal,
                      enabled: !running,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Goal'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Goal required'
                          : null,
                    ),
                  ),
                  IconButton(
                    key: const Key('prompt.settingsGear'),
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                    onPressed: () =>
                        setState(() => _settingsOpen = !_settingsOpen),
                  ),
                  running
                      ? ElevatedButton(
                          key: const Key('prompt.stop'),
                          onPressed: widget.onStop,
                          child: const Text('Stop'),
                        )
                      : ElevatedButton(
                          key: const Key('prompt.start'),
                          onPressed: _submit,
                          child: const Text('Start'),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns the configured swift-infer fallback model id, or `null` for
/// providers that don't expose a documented "always-available" model
/// (anthropic / openai — pointing users at their `defaultModelId`
/// would mislead them into pressing Start against the same broken
/// network).
String? _fallbackModelIdFor(ProviderConfig? cfg) =>
    cfg is SwiftInferUiConfig ? cfg.defaultModelId : null;

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.blueGrey.shade100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: const TextStyle(fontSize: 10)),
  );
}
