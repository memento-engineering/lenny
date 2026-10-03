import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:flutter/material.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;

/// Fixture exercising the connect-time diagnostic
/// `ext.leonard.core.diagnostics_warnings` from the host.
/// `HitScreen` contains a bare `GestureDetector` (one warning expected);
/// `CleanScreen` wraps the same gesture in a label-bearing `Semantics`
/// (zero warnings expected).
void main() {
  LeonardBinding.ensureInitialized(
    extensions: const <LeonardExtension>[CanonicalFixtureExtension()],
  );
  runApp(const MaterialApp(home: HitScreen()));
}

class CanonicalFixtureExtension extends LeonardExtension
    with PerceptionExtension {
  const CanonicalFixtureExtension();

  @override
  String get namespace => 'canonical_fixture';

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  genesis.Component buildPerception() => const CanonicalFixturePerception();

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class CanonicalFixturePerception extends genesis.StatelessPerception {
  const CanonicalFixturePerception({super.key});

  @override
  genesis.Component build(genesis.PerceptionContext context) =>
      const genesis.Node(
        'canonical_fixture',
        children: <genesis.Component>[genesis.Field('host', 'flutter')],
      );
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
