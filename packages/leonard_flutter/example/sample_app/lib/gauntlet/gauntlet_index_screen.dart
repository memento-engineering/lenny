import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'gauntlet_catalog.dart';

/// Index for the gauntlet: a list of scenario screens, each isolating one
/// real-world pitfall for the driving agent. Grouped by lane. Built
/// scenarios navigate to their route; the rest are shown as placeholders so
/// the full plan is legible.
class GauntletIndexScreen extends StatelessWidget {
  const GauntletIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> lanes = <String>[laneSettle, laneControls, laneVision];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gauntlet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        children: <Widget>[
          for (final String lane in lanes) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                lane,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            for (final GauntletScenario s in gauntletScenarios)
              if (s.lane == lane) _ScenarioTile(scenario: s),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.scenario});

  final GauntletScenario scenario;

  @override
  Widget build(BuildContext context) {
    final bool built = scenario.built;
    return ListTile(
      enabled: built,
      leading: Icon(
        built ? Icons.play_circle_outline : Icons.lock_clock,
        color: built ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(scenario.title),
      subtitle: Text(built ? scenario.trap : 'Not yet built'),
      isThreeLine: built,
      trailing: built ? const Icon(Icons.chevron_right) : null,
      onTap: built ? () => context.go(scenario.route) : null,
    );
  }
}
