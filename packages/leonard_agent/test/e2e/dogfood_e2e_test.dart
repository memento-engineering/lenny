/// End-to-end dogfood test.
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
///     bare-tool-name bug. When the model returns a bare
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
library;

import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart'
    show SchemaRejection, TrajectorySink;
import 'package:leonard_agent/src/dogfood/agent_dogfood_harness.dart';
import 'package:leonard_agent/src/dogfood/observation_fixture.dart';
import 'package:leonard_agent/src/dogfood/types.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_config.dart';
import 'package:leonard_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:test/test.dart';

import '../_support/leonard_vm_service_fake.dart';

const String _skipMessage =
    'SWIFT_INFER_ENDPOINT and SWIFT_INFER_AGENT_TOKEN must be set; '
    'run packages/leonard_agent/tool/agent_dogfood.dart for ad-hoc runs';

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
  test(
    'happyPathDarkMode',
    () async {
      final fake = LeonardVmServiceFake(
        handshakeResponse: <String, dynamic>{
          'protocolVersion': '2',
          'extensions': <dynamic>[],
        },
        observationBundle: ObservationFixture.empty().body,
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>?)
            >{
              'ext.exploration.router.navigate': (args) async {
                final String? raw = args?['route_name'] as String?;
                return <String, dynamic>{'ok': true, 'value': raw};
              },
              'ext.exploration.core.tap': (args) async {
                final Object? nodeId = args?['node_id'];
                return <String, dynamic>{'ok': true, 'node_id': nodeId};
              },
            },
      );
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
        reason:
            'tracePath=${r.tracePath} traceLines=${sink.lines.length} '
            'exception=${r.exception}',
      );
      expect(r.toolCallCount, greaterThanOrEqualTo(0));

      // Per-turn dogfood_turn lines must be emitted
      // whenever the LoopDriver actually entered a turn (i.e. the run
      // did NOT exit via a pre-turn typed exception). The
      // typedException outcome covers handshake-time failures where
      // zero turns ran; otherwise we require at least one turn line.
      final int turnLines = sink.lines
          .where((String l) => l.contains('"dogfood_turn"'))
          .length;
      if (r.outcome == DogfoodOutcome.completedWithToolCall ||
          r.outcome == DogfoodOutcome.completedNoToolCall) {
        expect(
          turnLines,
          greaterThanOrEqualTo(1),
          reason:
              'expected ≥1 dogfood_turn line for outcome '
              '${r.outcome.name}; got ${sink.lines}',
        );
      }
    },
    skip: _skipReason(),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'unknownToolNameSurvives',
    () async {
      final fake = LeonardVmServiceFake(
        handshakeResponse: <String, dynamic>{
          'protocolVersion': '2',
          'extensions': <dynamic>[],
        },
        observationBundle: ObservationFixture.empty().body,
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>?)
            >{
              'ext.exploration.router.navigate': (args) async {
                final String? raw = args?['route_name'] as String?;
                return <String, dynamic>{'ok': true, 'value': raw};
              },
            },
      );
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
        // Regression-lock: bare-tool-name from the model
        // must surface as SchemaRejection, never crash.
        expect(
          r.exception,
          isA<SchemaRejection>(),
          reason: 'unknown-tool path must fail closed at SchemaRejection',
        );
      }
    },
    skip: _skipReason(),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'emptyObservationDoesNotCrash',
    () async {
      final fake = LeonardVmServiceFake(
        handshakeResponse: <String, dynamic>{
          'protocolVersion': '2',
          'extensions': <dynamic>[],
        },
        observationBundle: ObservationFixture.empty().body,
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>?)
            >{
              'ext.exploration.core.tap': (args) async {
                final Object? nodeId = args?['node_id'];
                return <String, dynamic>{'ok': true, 'node_id': nodeId};
              },
            },
      );
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
      expect(
        r,
        isA<DogfoodRunResult>(),
        reason: 'tracePath=${r.tracePath} exception=${r.exception}',
      );
    },
    skip: _skipReason(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
