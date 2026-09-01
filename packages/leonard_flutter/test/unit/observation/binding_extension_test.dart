import 'dart:convert';
import 'dart:developer' as developer;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/src/observation/budgeted_json.dart'
    show kCoreBudgetBytes;
import 'package:flutter/foundation.dart' hide DiagnosticsProperty;
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

const String _ext = 'ext.leonard.core.get_stable_observation';
const String _diagExt = 'ext.leonard.core.get_diagnostics_tree';

class _ExtensionA extends LeonardExtension with PerceptionExtension {
  const _ExtensionA();
  @override
  String get namespace => 'a';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Seed buildPerception() =>
      Node('a', children: <Seed>[Field('extensionA', true)]);
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _ExtensionB extends LeonardExtension with PerceptionExtension {
  const _ExtensionB();
  @override
  String get namespace => 'b';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Seed buildPerception() => Node('b', children: <Seed>[Field('extensionB', 1)]);
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}


/// Perception extension that always reports idle — its fragment/subtree
/// must be OMITTED from both observation and diagnostics.
class _IdleExtension extends LeonardExtension with PerceptionExtension {
  const _IdleExtension();
  @override
  String get namespace => 'idle_ext';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  bool isPerceptionIdle() => true;
  @override
  Seed buildPerception() =>
      Node('idle_ext', children: <Seed>[Field('neverEmitted', true)]);
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

/// Perception extension whose buildPerception throws — the binding must
/// ISOLATE the failure (no subtree, call still succeeds).
class _ThrowingExtension extends LeonardExtension with PerceptionExtension {
  const _ThrowingExtension();
  @override
  String get namespace => 'throwing';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Seed buildPerception() => throw StateError('boom in diagnostics build');
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

/// Perception extension with a chunky payload — small enough to fit the
/// default diagnostics budget, big enough that a lowered test budget
/// drops subtrees from the tail.
class _OversizedExtension extends LeonardExtension with PerceptionExtension {
  const _OversizedExtension();
  @override
  String get namespace => 'oversized';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Seed buildPerception() =>
      Node('oversized', children: <Seed>[Field('payload', 'x' * 400)]);
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

/// Every property name reachable in [node]'s subtree (top-level property
/// names only — nested object properties keep their carrier's name).
Set<String> _propertyNames(TreeNode node) => <String>{
  for (final DiagnosticsProperty p in node.properties) p.name,
  for (final TreeNode c in node.children) ..._propertyNames(c),
};

void main() {
  // Plain test() (not testWidgets) — once a Flutter binding is installed
  // in a process it cannot be torn down (PRD §6.5), so all assertions
  // share one binding via setUpAll.
  late LeonardBinding binding;
  // Scripted clock for the policy loop's `nowMs` so a one-iteration
  // `budget` termination is deterministic. First call returns 0,
  // subsequent calls return values past the action-relative budget.
  final List<int> clockTicks = <int>[0, 100, 100, 100];
  int clockIdx = 0;
  int now() =>
      clockTicks[clockIdx < clockTicks.length
          ? clockIdx++
          : clockTicks.length - 1];

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(
      extensions: const <LeonardExtension>[
        _ExtensionA(),
        _ExtensionB(),
        _IdleExtension(),
        _ThrowingExtension(),
        _OversizedExtension(),
      ],
    )!;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {},
      nowMs: now,
    );
  });

  setUp(() {
    clockIdx = 0;
  });

  group('Registration', () {
    test('extension is registered exactly once in debug mode', () {
      if (kReleaseMode) {
        expect(binding.debugHasRegisteredExtension(_ext), isFalse);
        return;
      }
      if (kProfileMode) {
        // AC: kDebugMode-gated; profile-only builds must NOT register.
        expect(binding.debugHasRegisteredExtension(_ext), isFalse);
        return;
      }
      expect(binding.debugHasRegisteredExtension(_ext), isTrue);
      // Re-registering throws -> name was already taken via our path.
      expect(
        () => developer.registerExtension(
          _ext,
          (String m, Map<String, String> p) async =>
              developer.ServiceExtensionResponse.result('{}'),
        ),
        throwsArgumentError,
      );
    });
  });

  // The framework registers persistent frame callbacks at boot, so
  // `frameworkBusySnapshot().isAnyBusy` is true under tests. Drive the
  // loop with a tiny action-relative budget so it terminates on
  // `budget` rather than waiting for an idle frame that never comes.
  Map<String, String> params() => <String, String>{
    'actionRelativeBudgetMs': '1',
  };

  group('MergedShape', () {
    test('single VM call returns full merged bundle', () async {
      if (!kDebugMode) return;
      final String body = await binding.invokeServiceExtension(_ext, params());
      final Map<String, Object?> outer =
          jsonDecode(body) as Map<String, Object?>;
      expect(outer['type'], 'Observation');
      final Map<String, Object?> obs = outer['value']! as Map<String, Object?>;
      expect(
        obs.keys,
        containsAll(<String>[
          'semantics',
          'routes',
          'errors',
          'stability',
          'extensions',
        ]),
      );
      final Map<String, Object?> stability =
          obs['stability']! as Map<String, Object?>;
      expect(stability['policy'], 'action-relative');
      // Either idle or budget — either is a valid first-iteration termination.
      expect(<String>['idle', 'budget'], contains(stability['terminated_by']));
      expect(stability['framework_busy'], isMap);
      expect(stability['extensions_busy'], isList);
    });

    test('small core budget degrades without erasing metadata', () async {
      if (!kDebugMode) return;
      final String body = await binding.invokeServiceExtension(
        _ext,
        <String, String>{
          'actionRelativeBudgetMs': '1',
          'coreBudgetBytes': '256',
        },
      );
      final Map<String, Object?> obs =
          (jsonDecode(body) as Map<String, Object?>)['value']!
              as Map<String, Object?>;

      expect(obs['routes'], isList);
      expect(obs['errors'], isList);
      expect(obs['stability'], isMap);
      expect(obs['_truncated'], isTrue);
      expect(obs['budgetBytes'], 256);
      expect(obs['droppedNodes'], isA<int>());
    });
  });

  group('ExtensionOrder', () {
    test(
      'extension fragments preserve registration order under "extensions"',
      () async {
        if (!kDebugMode) return;
        final String body = await binding.invokeServiceExtension(
          _ext,
          params(),
        );
        final Map<String, Object?> obs =
            (jsonDecode(body) as Map<String, Object?>)['value']!
                as Map<String, Object?>;
        final Map<String, Object?> extensions =
            obs['extensions']! as Map<String, Object?>;
        // Registration order, with the idle extension suppressed and the
        // throwing extension isolated.
        expect(extensions.keys.toList(), <String>['a', 'b', 'oversized']);
        expect(
          (extensions['a']! as Map<String, Object?>)['extensionA'],
          isTrue,
        );
        expect((extensions['b']! as Map<String, Object?>)['extensionB'], 1);
      },
    );
  });

  group('DiagnosticsTree', () {
    test('sibling extension is registered in debug mode', () {
      if (!kDebugMode) {
        expect(binding.debugHasRegisteredExtension(_diagExt), isFalse);
        return;
      }
      expect(binding.debugHasRegisteredExtension(_diagExt), isTrue);
    });

    test(
      'on-demand tree: contract 1, UTC stamp, root identity, core-first '
      'registry order, idle omission, throw isolation',
      () async {
        if (!kDebugMode) return;
        await Future<void>.delayed(Duration.zero);
        final String body = await binding.invokeServiceExtension(
          _diagExt,
          const <String, String>{},
        );
        final Map<String, Object?> out =
            jsonDecode(body) as Map<String, Object?>;
        expect(out['truncated'], isFalse);
        final TreeSnapshot snap = TreeSnapshot.fromJson(
          (out['diagnostics_tree']! as Map).cast<String, Object?>(),
        );
        expect(snap.contractVersion, 1);
        expect(snap.projectedAt.isUtc, isTrue);
        expect(snap.root.seedType, 'LeonardObservation');
        expect(snap.root.id, 'leonard:observation');
        // Core first, then registry order (a, b, oversized). The idle
        // extension is omitted; the throwing extension is isolated (no
        // subtree, but the call still succeeded).
        final List<TreeNode> children = snap.root.children;
        expect(children, hasLength(4));
        expect(
          _propertyNames(children[0]),
          containsAll(<String>['semantics', 'routes', 'errors', 'stability']),
        );
        expect(_propertyNames(children[1]), contains('extensionA'));
        expect(_propertyNames(children[2]), contains('extensionB'));
        expect(_propertyNames(children[3]), contains('payload'));
        for (final TreeNode child in children) {
          expect(_propertyNames(child), isNot(contains('neverEmitted')));
        }
      },
    );

    test(
      'low budget truncates from the tail; root stays decodable',
      () async {
        if (!kDebugMode) return;
        await Future<void>.delayed(Duration.zero);
        final String fullBody = await binding.invokeServiceExtension(
          _diagExt,
          const <String, String>{},
        );
        final Map<String, Object?> fullOut =
            jsonDecode(fullBody) as Map<String, Object?>;
        expect(fullOut['truncated'], isFalse);
        final TreeSnapshot full = TreeSnapshot.fromJson(
          (fullOut['diagnostics_tree']! as Map).cast<String, Object?>(),
        );
        final int fullBytes = utf8
            .encode(jsonEncode(full.toJson()))
            .length;
        try {
          binding.debugSetDiagnosticsBudgetForTesting(fullBytes - 1);
          final String body = await binding.invokeServiceExtension(
            _diagExt,
            const <String, String>{},
          );
          final Map<String, Object?> out =
              jsonDecode(body) as Map<String, Object?>;
          expect(out['truncated'], isTrue);
          // The truncated payload must still decode under contract 1 —
          // whole extension subtrees were dropped from the tail, never
          // replaced with a marker blob.
          final TreeSnapshot snap = TreeSnapshot.fromJson(
            (out['diagnostics_tree']! as Map).cast<String, Object?>(),
          );
          expect(snap.contractVersion, 1);
          expect(snap.root.seedType, 'LeonardObservation');
          expect(snap.root.id, 'leonard:observation');
          expect(
            snap.root.children.length,
            lessThan(full.root.children.length),
          );
          if (snap.root.children.isNotEmpty) {
            // Core-first survives truncation.
            expect(
              _propertyNames(snap.root.children.first),
              containsAll(<String>['semantics', 'stability']),
            );
          }
        } finally {
          binding.debugSetDiagnosticsBudgetForTesting(kCoreBudgetBytes);
        }
      },
    );

    test('budget setter rejects non-positive values', () {
      expect(
        () => binding.debugSetDiagnosticsBudgetForTesting(0),
        throwsArgumentError,
      );
      expect(
        () => binding.debugSetDiagnosticsBudgetForTesting(-1),
        throwsArgumentError,
      );
    });
  });
}
