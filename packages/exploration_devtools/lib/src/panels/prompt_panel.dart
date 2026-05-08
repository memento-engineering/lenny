import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry;
import 'package:flutter/material.dart';

import 'prompt_panel_config.dart';

/// Goal / model / budget / plugin form rendered into the DevTools
/// extension's Prompt tab. Stateless w.r.t. running session — owners pass
/// [running] in and react to [onStart] / [onStop] callbacks.
///
/// PRD §6.3 and AC for cx6.22: replaces CLI argument parsing for the
/// interactive DevTools flow.
class PromptPanel extends StatefulWidget {
  const PromptPanel({
    super.key,
    required this.availableModels,
    required this.plugins,
    required this.running,
    required this.onStart,
    required this.onStop,
    this.pluginGuideUrl =
        'https://example.com/exploration-agent/plugin-authoring',
  });

  /// Models surfaced in the dropdown. Comes from cx6.14/.15/.16 wiring;
  /// the widget never hardcodes ids.
  final List<ModelDescriptor> availableModels;

  /// Plugin manifest from the binding handshake (cx6.11). Empty list
  /// renders the empty-state guide hint instead of toggles.
  final List<PluginManifestEntry> plugins;

  /// `true` while a session is in flight. Disables every input and
  /// swaps the Start button for Stop.
  final bool running;

  /// Invoked when the user submits a valid form.
  final void Function(PromptPanelConfig) onStart;

  /// Invoked when the user presses Stop while [running] is true.
  final VoidCallback onStop;

  /// URL surfaced in the empty-plugin hint (cx6.35).
  final String pluginGuideUrl;

  @override
  State<PromptPanel> createState() => _PromptPanelState();
}

class _PromptPanelState extends State<PromptPanel> {
  late final TextEditingController _goal = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late String _modelId = widget.availableModels.first.id;
  int _maxTurns = 50;
  Duration _budget = const Duration(minutes: 15);
  late final Set<String> _enabled =
      widget.plugins.map((p) => p.namespace).toSet();

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onStart(PromptPanelConfig(
      goal: _goal.text,
      modelId: _modelId,
      maxTurns: _maxTurns,
      wallClockBudget: _budget,
      enabledPluginNamespaces: _enabled,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.running;
    final children = <Widget>[
      TextFormField(
        key: const Key('prompt.goal'),
        controller: _goal,
        enabled: !running,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Goal'),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Goal required' : null,
      ),
      DropdownButtonFormField<String>(
        key: const Key('prompt.model'),
        initialValue: _modelId,
        items: widget.availableModels
            .map((m) => DropdownMenuItem(value: m.id, child: Text(m.label)))
            .toList(),
        onChanged:
            running ? null : (v) => setState(() => _modelId = v ?? _modelId),
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
        decoration: const InputDecoration(labelText: 'Wall-clock budget (minutes)'),
        onChanged: (v) =>
            _budget = Duration(minutes: int.tryParse(v) ?? 15),
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
    ];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}
