import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — lazy off-screen target.
///
/// A `ListView.builder` of 200 rows. The target (row 150) is not built — and
/// therefore not in the semantics tree — until the agent scrolls it into
/// view. The agent must scroll, find it, then tap it.
///
/// Action oracle: `goal_reached` flips when row 150 is tapped.
class LazyOffscreenScreen extends StatelessWidget {
  const LazyOffscreenScreen({super.key});

  static const String scenarioId = 'control/lazy-offscreen';
  static const int targetRow = 150;
  static const int rowCount = 200;

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: scenarioId,
      expected: const <String, Object?>{'target_row': targetRow},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lazy off-screen'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: ListView.builder(
          itemCount: rowCount,
          itemBuilder: (BuildContext context, int i) {
            final bool isTarget = i == targetRow;
            return ListTile(
              leading: CircleAvatar(child: Text('$i')),
              title: Text('Row $i'),
              trailing: isTarget ? const Icon(Icons.flag) : null,
              onTap: isTarget ? () => markGoalReached(scenarioId) : null,
            );
          },
        ),
      ),
    );
  }
}
