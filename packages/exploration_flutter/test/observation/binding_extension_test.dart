import 'dart:convert';
import 'dart:developer' as developer;

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const String _ext =
    'ext.flutter.exploration.core.get_stable_observation';

class _PluginA extends ExplorationPlugin {
  const _PluginA();
  @override
  String get namespace => 'a';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async =>
      <String, Object?>{'pluginA': true, 'turn': ctx.turn};
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _PluginB extends ExplorationPlugin {
  const _PluginB();
  @override
  String get namespace => 'b';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async =>
      <String, Object?>{'pluginB': 1};
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
  late ExplorationBinding binding;
  // Scripted clock for the policy loop's `nowMs` so a one-iteration
  // `budget` termination is deterministic. First call returns 0,
  // subsequent calls return values past the action-relative budget.
  final List<int> clockTicks = <int>[0, 100, 100, 100];
  int clockIdx = 0;
  int now() => clockTicks[clockIdx < clockTicks.length
      ? clockIdx++
      : clockTicks.length - 1];

  setUpAll(() {
    binding = ExplorationBinding.ensureInitialized(
      plugins: const <ExplorationPlugin>[_PluginA(), _PluginB()],
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
        'plugins',
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
      expect(stability['plugins_busy'], isList);
    });
  });

  group('PluginOrder', () {
    test('plugin fragments preserve registration order under "plugins"',
        () async {
      if (!kDebugMode) return;
      final String body =
          await binding.invokeServiceExtension(_ext, params());
      final Map<String, Object?> obs = (jsonDecode(body)
          as Map<String, Object?>)['value']! as Map<String, Object?>;
      final Map<String, Object?> plugins =
          obs['plugins']! as Map<String, Object?>;
      expect(plugins.keys.toList(), <String>['a', 'b']);
      expect((plugins['a']! as Map<String, Object?>)['pluginA'], isTrue);
      expect((plugins['b']! as Map<String, Object?>)['pluginB'], 1);
    });
  });
}
