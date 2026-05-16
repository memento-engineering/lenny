/// End-to-end dogfood test (bead lenny-cx6.43).
///
/// Drives the shared [AgentDogfoodHarness] against a live swift-infer
/// endpoint. Skips when either of the required env vars
/// (`SWIFT_INFER_ENDPOINT`, `SWIFT_INFER_AGENT_TOKEN`) is unset so the
/// default `flutter test` invocation does NOT hang or attempt network
/// IO. The CLI sibling (`tool/agent_dogfood.dart`) is the ad-hoc
/// prompt-tuning entry point.
///
/// Three canonical scenarios:
///
///   * `happyPathDarkMode` — goal "turn on dark mode" on a fixture
///     login screen with `[router.navigate, core.tap]`. The model is
///     free to call either tool; the assertion only checks that the
///     loop completes (or surfaces a typedException) with the trace
///     and tool-call count reported.
///   * `unknownToolNameSurvives` — regression-lock for the qwen3.6-27b
///     bare-tool-name bug (cx6.40). When the model returns a bare
///     `navigate` without the namespace prefix, the harness must
///     surface `outcome == typedException` with a `SchemaRejection`
///     cause, NOT crash.
///   * `emptyObservationDoesNotCrash` — single-turn run with no
///     fixture; the harness must complete without an unhandled
///     exception regardless of the model's response.
///
/// On failure, each scenario prints `tracePath` so the swift-infer
/// `request_id` can be cross-referenced via the `debug-inference`
/// admin skill.
///
// ignore_for_file: invalid_use_of_visible_for_testing_member
//
// `debugSetPolicyLoopSeamsForTesting` is `@visibleForTesting`; this
// test is the explicit test that needs it. Suppressed here to keep
// analyzer-clean.
library;

import 'dart:io';

import 'package:exploration_agent/exploration_agent.dart'
    show SchemaRejection, TrajectorySink;
import 'package:exploration_agent/src/dogfood/agent_dogfood_harness.dart';
import 'package:exploration_agent/src/dogfood/observation_fixture.dart';
import 'package:exploration_agent/src/dogfood/types.dart';
import 'package:exploration_agent/src/provider/swift_infer/swift_infer_config.dart';
import 'package:exploration_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/binding_vm_service_fake.dart';

const String _skipMessage =
    'SWIFT_INFER_ENDPOINT and SWIFT_INFER_AGENT_TOKEN must be set; '
    'run packages/exploration_agent/tool/agent_dogfood.dart for ad-hoc runs';

Object? _skipReason() {
  final String? e = Platform.environment['SWIFT_INFER_ENDPOINT'];
  final String? t = Platform.environment['SWIFT_INFER_AGENT_TOKEN'];
  if (e == null || e.isEmpty || t == null || t.isEmpty) return _skipMessage;
  return null;
}

/// In-memory [TrajectorySink] so tests don't litter `/tmp`. The trace
/// path field on `DogfoodRunResult` carries the literal `'<memory>'`
/// for diagnostics.
class _MemorySink implements TrajectorySink {
  final List<String> lines = <String>[];
  @override
  Future<void> writeLine(String l) async => lines.add(l);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

class _NoopTool extends ExplorationTool {
  _NoopTool(this._name);
  final String _name;
  @override
  String get name => _name;
  @override
  String get description => 'dogfood stand-in for $_name';
  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
      });
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args);
}

class _RouterPlugin extends ExplorationPlugin {
  @override
  String get namespace => 'router';
  @override
  List<ExplorationTool> get tools => <ExplorationTool>[_NoopTool('navigate')];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

const ToolDescriptor _navigateTool = ToolDescriptor(
  name: 'router.navigate',
  description: 'navigate to a named route',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'route_name': <String, dynamic>{'type': 'string'},
    },
    'required': <String>['route_name'],
  },
);

const ToolDescriptor _tapTool = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node by id',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'node_id': <String, dynamic>{'type': 'integer'},
    },
    'required': <String>['node_id'],
  },
);

SwiftInferConfig _config({String? conversationId}) => SwiftInferConfig(
      baseUrl: Uri.parse(Platform.environment['SWIFT_INFER_ENDPOINT']!),
      model: 'qwen3.6-27b',
      bearerToken: Platform.environment['SWIFT_INFER_AGENT_TOKEN']!,
      captureBodies: true,
      conversationId: conversationId,
    );

void main() {
  // We allocate the binding inside each test so a teardown failure in
  // one scenario doesn't poison the others. The skip check fires on
  // both the `skip:` argument AND inside the test body so default
  // `flutter test` runs do zero work.
  Future<ExplorationBinding> bootBinding() async {
    final ExplorationBinding binding = ExplorationBinding.ensureInitialized(
      plugins: <ExplorationPlugin>[_RouterPlugin()],
    )!;
    await Future<void>.delayed(Duration.zero);
    int now = 0;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {
        now += 16;
      },
      nowMs: () => now,
    );
    return binding;
  }

  test('happyPathDarkMode', () async {
    final ExplorationBinding binding = await bootBinding();
    final fake = BindingVmServiceFake(binding);
    final sink = _MemorySink();
    final harness = AgentDogfoodHarness(
      vm: fake,
      isolateId: 'isolate-0',
      swiftInferConfig: _config(conversationId: 'dogfood-e2e-happyPath'),
      goal: 'turn on dark mode',
      tools: const <ToolDescriptor>[_navigateTool, _tapTool],
      fixture: ObservationFixture.empty(),
      maxTurns: 2,
      maxTurnBudgetMs: 30000,
      traceSink: sink,
      tracePath: '<memory>',
    );
    final DogfoodRunResult r = await harness.run();
    expect(
      r.outcome,
      anyOf(<DogfoodOutcome>[
        DogfoodOutcome.completedWithToolCall,
        DogfoodOutcome.completedNoToolCall,
        DogfoodOutcome.typedException,
      ]),
      reason: 'tracePath=${r.tracePath} traceLines=${sink.lines.length} '
          'exception=${r.exception}',
    );
    expect(r.toolCallCount, greaterThanOrEqualTo(0));
  }, skip: _skipReason(), timeout: const Timeout(Duration(minutes: 5)));

  test('unknownToolNameSurvives', () async {
    final ExplorationBinding binding = await bootBinding();
    final fake = BindingVmServiceFake(binding);
    final sink = _MemorySink();
    final harness = AgentDogfoodHarness(
      vm: fake,
      isolateId: 'isolate-0',
      swiftInferConfig: _config(conversationId: 'dogfood-e2e-unknownTool'),
      // The goal text historically triggered qwen3.6-27b to drop the
      // namespace prefix and return a bare `navigate` tool name.
      goal: 'navigate to the home screen',
      tools: const <ToolDescriptor>[_navigateTool],
      fixture: ObservationFixture.empty(),
      maxTurns: 2,
      maxTurnBudgetMs: 30000,
      traceSink: sink,
      tracePath: '<memory>',
    );
    final DogfoodRunResult r = await harness.run();
    expect(
      r.outcome,
      anyOf(<DogfoodOutcome>[
        DogfoodOutcome.completedWithToolCall,
        DogfoodOutcome.completedNoToolCall,
        DogfoodOutcome.typedException,
      ]),
      reason: 'tracePath=${r.tracePath} exception=${r.exception}',
    );
    if (r.outcome == DogfoodOutcome.typedException) {
      // Regression-lock for cx6.40: bare-tool-name from the model
      // must surface as SchemaRejection, never crash.
      expect(r.exception, isA<SchemaRejection>(),
          reason: 'unknown-tool path must fail closed at SchemaRejection');
    }
  }, skip: _skipReason(), timeout: const Timeout(Duration(minutes: 5)));

  test('emptyObservationDoesNotCrash', () async {
    final ExplorationBinding binding = await bootBinding();
    final fake = BindingVmServiceFake(binding);
    final sink = _MemorySink();
    final harness = AgentDogfoodHarness(
      vm: fake,
      isolateId: 'isolate-0',
      swiftInferConfig: _config(conversationId: 'dogfood-e2e-empty'),
      goal: 'do something',
      tools: const <ToolDescriptor>[_tapTool],
      fixture: ObservationFixture.empty(),
      maxTurns: 1,
      maxTurnBudgetMs: 30000,
      traceSink: sink,
      tracePath: '<memory>',
    );
    // Any outcome is acceptable — the assertion is "the future
    // completes". A typed result implies no unhandled exception.
    final DogfoodRunResult r = await harness.run();
    expect(r, isA<DogfoodRunResult>(),
        reason: 'tracePath=${r.tracePath} exception=${r.exception}');
  }, skip: _skipReason(), timeout: const Timeout(Duration(minutes: 5)));
}
