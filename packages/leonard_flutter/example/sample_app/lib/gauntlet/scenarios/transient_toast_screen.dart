import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane A — transient toast.
///
/// Tapping "Submit" shows a snackbar 500ms later that auto-dismisses after
/// 2.5s. The confirmation message only exists in that window: observe too
/// early (before 500ms) or too late (after it dismisses) and it is gone.
///
/// Answer oracle: expected.message_contains == 'draft #7'. `goal_reached`
/// also flips when the toast is shown, as a secondary signal.
class TransientToastScreen extends StatefulWidget {
  const TransientToastScreen({super.key});

  static const String scenarioId = 'settle/transient-toast';
  static const String message = 'Saved as draft #7';

  @override
  State<TransientToastScreen> createState() => _TransientToastScreenState();
}

class _TransientToastScreenState extends State<TransientToastScreen> {
  Timer? _timer;

  void _submit() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      markGoalReached(TransientToastScreen.scenarioId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(TransientToastScreen.message),
          duration: Duration(milliseconds: 2500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: TransientToastScreen.scenarioId,
      expected: const <String, Object?>{'message_contains': 'draft #7'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transient toast'),
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
              const Text('Submit, then read the confirmation message.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Submit'),
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
