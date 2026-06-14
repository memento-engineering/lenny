import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';

/// Fixture for cx6.10 — exercises the connect-time diagnostic
/// `ext.exploration.core.diagnostics_warnings` from the host.
/// `HitScreen` contains a bare `GestureDetector` (one warning expected);
/// `CleanScreen` wraps the same gesture in a label-bearing `Semantics`
/// (zero warnings expected).
void main() {
  ExplorationBinding.ensureInitialized(plugins: const <ExplorationPlugin>[]);
  runApp(const MaterialApp(home: HitScreen()));
}

class HitScreen extends StatelessWidget {
  const HitScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(width: 80, height: 80, color: Colors.red),
          ),
        ),
      );
}

class CleanScreen extends StatelessWidget {
  const CleanScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Semantics(
            label: 'red square',
            button: true,
            child: GestureDetector(
              onTap: () {},
              child: Container(width: 80, height: 80, color: Colors.red),
            ),
          ),
        ),
      );
}
