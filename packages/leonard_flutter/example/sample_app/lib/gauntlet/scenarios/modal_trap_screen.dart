import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — modal focus trap.
///
/// A barrier dialog pops on entry and swallows taps to the "Open Settings"
/// button behind it (barrierDismissible is false). The agent must dismiss
/// the dialog ("Got it") before it can reach Settings — tapping Settings
/// while the modal is up does nothing.
///
/// Action oracle: `goal_reached` flips when Settings is opened, which is
/// only possible once the dialog is dismissed.
class ModalTrapScreen extends StatefulWidget {
  const ModalTrapScreen({super.key});

  static const String scenarioId = 'control/modal-trap';

  @override
  State<ModalTrapScreen> createState() => _ModalTrapScreenState();
}

class _ModalTrapScreenState extends State<ModalTrapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showBlocker());
  }

  void _showBlocker() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notice'),
          content: const Text('Dismiss this dialog before continuing.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: ModalTrapScreen.scenarioId,
      expected: const <String, Object?>{
        'action': 'open settings after dismissing the dialog',
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Modal trap'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            onPressed: () => markGoalReached(ModalTrapScreen.scenarioId),
          ),
        ),
      ),
    );
  }
}
