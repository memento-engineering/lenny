import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — hidden until expanded.
///
/// The "Airplane mode" switch lives inside a collapsed [ExpansionTile], so it
/// is NOT in the semantics tree until the agent expands the section. The
/// agent must first tap "Advanced", then toggle the switch.
///
/// Action oracle: `goal_reached` flips when airplane mode is turned on.
class ExpandToReachScreen extends StatefulWidget {
  const ExpandToReachScreen({super.key});

  static const String scenarioId = 'control/expand-to-reach';

  @override
  State<ExpandToReachScreen> createState() => _ExpandToReachScreenState();
}

class _ExpandToReachScreenState extends State<ExpandToReachScreen> {
  bool _airplane = false;

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: ExpandToReachScreen.scenarioId,
      expected: const <String, Object?>{'action': 'enable airplane mode'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expand to reach'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: ListView(
          children: <Widget>[
            const ListTile(title: Text('Turn on airplane mode.')),
            ExpansionTile(
              title: const Text('Advanced'),
              children: <Widget>[
                SwitchListTile(
                  title: const Text('Airplane mode'),
                  value: _airplane,
                  onChanged: (bool v) {
                    setState(() => _airplane = v);
                    if (v) markGoalReached(ExpandToReachScreen.scenarioId);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
