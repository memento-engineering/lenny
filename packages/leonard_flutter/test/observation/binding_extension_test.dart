import 'dart:convert';
import 'dart:developer' as developer;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

const String _ext =
    'ext.exploration.core.get_stable_observation';

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
      Node('a', children: <Seed>[Field('pluginA', true)]);
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
  Seed buildPerception() => Node('b', children: <Seed>[Field('pluginB', 1)]);
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

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
  int now() => clockTicks[clockIdx < clockTicks.length
      ? clockIdx++
      : clockTicks.length - 1];

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(
      plugins: const <LeonardExtension>[_ExtensionA(), _ExtensionB()],
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
      final String body =
          await binding.invokeServiceExtension(_ext, params());
      final Map<String, Object?> outer =
          jsonDecode(body) as Map<String, Object?>;
      expect(outer['type'], 'Observation');
      final Map<String, Object?> obs =
          outer['value']! as Map<String, Object?>;
      expect(obs.keys, containsAll(<String>[
        'semantics',
        'routes',
        'errors',
        'stability',
        'extensions',
      ]));
      final Map<String, Object?> stability =
          obs['stability']! as Map<String, Object?>;
      expect(stability['policy'], 'action-relative');
      // Either idle or budget — either is a valid first-iteration termination.
      expect(
        <String>['idle', 'budget'],
        contains(stability['terminated_by']),
      );
      expect(stability['framework_busy'], isMap);
      expect(stability['extensions_busy'], isList);
    });
  });

  group('PluginOrder', () {
    test('plugin fragments preserve registration order under "extensions"',
        () async {
      if (!kDebugMode) return;
      final String body =
          await binding.invokeServiceExtension(_ext, params());
      final Map<String, Object?> obs = (jsonDecode(body)
          as Map<String, Object?>)['value']! as Map<String, Object?>;
      final Map<String, Object?> plugins =
          obs['extensions']! as Map<String, Object?>;
      expect(plugins.keys.toList(), <String>['a', 'b']);
      expect((plugins['a']! as Map<String, Object?>)['pluginA'], isTrue);
      expect((plugins['b']! as Map<String, Object?>)['pluginB'], 1);
    });
  });
}
