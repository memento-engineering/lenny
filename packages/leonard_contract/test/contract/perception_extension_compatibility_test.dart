// ignore_for_file: deprecated_member_use

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:test/test.dart';

void main() {
  test(
    'canonical and deprecated overrides remain synchronous and identical',
    () {
      const CanonicalExtension canonical = CanonicalExtension();
      const LegacyExtension legacy = LegacyExtension();
      final Component Function() canonicalBuild = canonical.buildPerception;
      final Seed Function() legacyBuild = legacy.buildPerception;
      final PerceptionOwner owner = PerceptionOwner();

      final Element canonicalRoot = owner.mountRoot(canonicalBuild());
      final Map<String, Object?> canonicalFragment =
          serializePerceptionFragment(canonicalRoot);
      owner.unmountRoot();

      final Element legacyRoot = owner.mountRoot(legacyBuild());
      final Map<String, Object?> legacyFragment = serializePerceptionFragment(
        legacyRoot,
      );
      owner.dispose();

      expect(legacyFragment, canonicalFragment);
      expect(canonicalFragment, <String, Object?>{'value': 1});
    },
  );
}

class CanonicalExtension extends LeonardExtension with PerceptionExtension {
  const CanonicalExtension();

  @override
  String get namespace => 'canonical';

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Component buildPerception() => const _ExamplePerception();

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class LegacyExtension extends LeonardExtension with PerceptionExtension {
  const LegacyExtension();

  @override
  String get namespace => 'legacy';

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Seed buildPerception() => const _ExamplePerception();

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class _ExamplePerception extends StatelessPerception {
  const _ExamplePerception();

  @override
  Component build(PerceptionContext context) =>
      const Node('example', children: <Component>[Field('value', 1)]);
}
