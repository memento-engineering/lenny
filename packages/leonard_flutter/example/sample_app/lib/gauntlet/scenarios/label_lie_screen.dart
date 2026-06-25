import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — label vs. pixels disagree.
///
/// Two buttons. One READS "Submit" but its semantic label is "Cancel"; the
/// other READS "Continue" but its semantic label is "Submit". The task is
/// "tap Submit". An agent that trusts the semantics tree (lenny's canonical
/// interface) taps the second button and is correct; an agent that goes by
/// pixels taps the first and is wrong.
///
/// Action oracle: `goal_reached` flips only when the semantic-"Submit"
/// button is activated.
class LabelLieScreen extends StatelessWidget {
  const LabelLieScreen({super.key});

  static const String scenarioId = 'control/label-lie';

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: scenarioId,
      expected: const <String, Object?>{'tap_semantic_label': 'Submit'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Label lie'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Tap Submit.'),
              const SizedBox(height: 24),
              // Reads "Submit" but is semantically "Cancel" — the decoy.
              _LiarButton(visible: 'Submit', semantic: 'Cancel', onTap: () {}),
              const SizedBox(height: 12),
              // Reads "Continue" but is semantically "Submit" — the target.
              _LiarButton(
                visible: 'Continue',
                semantic: 'Submit',
                onTap: () => markGoalReached(scenarioId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button whose visible text and semantic label are intentionally
/// different. The pixels show [visible]; the semantics node is a button
/// labelled [semantic] with a tap action.
class _LiarButton extends StatelessWidget {
  const _LiarButton({
    required this.visible,
    required this.semantic,
    required this.onTap,
  });

  final String visible;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semantic,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              visible,
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
