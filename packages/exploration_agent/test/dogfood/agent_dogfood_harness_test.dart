/// Unit tests for [AgentDogfoodHarness] (bead lenny-cx6.43, step 5).
///
/// These tests do NOT exercise swift-infer — that is the role of
/// `test/e2e/dogfood_e2e_test.dart`. Here we wire stub `VmService`s to
/// drive the harness through its two non-happy outcomes
/// (budgetExceeded, typedException) and assert the typed result shape.
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show BindingNotInitializedError, TrajectorySink;
import 'package:exploration_agent/src/dogfood/agent_dogfood_harness.dart';
import 'package:exploration_agent/src/dogfood/observation_fixture.dart';
import 'package:exploration_agent/src/dogfood/types.dart';
import 'package:exploration_agent/src/provider/swift_infer/swift_infer_config.dart';
import 'package:exploration_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _MemorySink implements TrajectorySink {
  final List<String> lines = <String>[];
  bool closed = false;
  @override
  Future<void> writeLine(String l) async => lines.add(l);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async => closed = true;
}

/// VmService whose callServiceExtension future never completes — used
/// to assert the per-turn / total-run budget terminates the harness.
class _HangingVmService extends VmService {
  _HangingVmService() : super(const Stream<dynamic>.empty(), (_) {});
  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) {
    final Completer<Response> c = Completer<Response>();
    // Never completes — caller's timeout takes over.
    return c.future;
  }

  @override
  Future<void> dispose() async {}
}

/// VmService that returns a successful handshake but hangs on every
/// subsequent call. Drives the harness through `session.start()`
/// (which calls `ext.flutter.exploration.core.handshake`) and into
/// the LoopDriver's per-turn observation pull, which hangs until the
/// per-turn budget trips. Used to assert that the original failure
/// surfaces — not the historic `StateError: writeHeader must precede`
/// (lenny-cx6.44 step 1 fix).
class _HandshakeOkThenHangingVmService extends VmService {
  _HandshakeOkThenHangingVmService()
      : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) {
    if (method == 'ext.flutter.exploration.core.handshake') {
      return Future<Response>.value(
        Response.parse(<String, dynamic>{
          'type': 'Response',
          'protocolVersion': '1',
          'plugins': <dynamic>[],
        })!,
      );
    }
    final Completer<Response> c = Completer<Response>();
    return c.future; // hang
  }

  @override
  Future<void> dispose() async {}
}

/// VmService that responds to every call with method-not-found, the
/// JSON-RPC -32601 code the agent's [VmServiceClient] translates into
/// [BindingNotInitializedError] on handshake.
class _RejectingVmService extends VmService {
  _RejectingVmService() : super(const Stream<dynamic>.empty(), (_) {});
  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    throw RPCError(method, -32601, 'Unknown method "$method"');
  }

  @override
  Future<void> dispose() async {}
}

final SwiftInferConfig _config = SwiftInferConfig(
  baseUrl: Uri.parse('http://127.0.0.1:1'),
  model: 'qwen3.6-27b',
  bearerToken: 'unused-in-unit-test',
);

const List<ToolDescriptor> _tools = <ToolDescriptor>[
  ToolDescriptor(
    name: 'core.tap',
    description: 'tap a node',
    inputSchema: <String, dynamic>{'type': 'object'},
  ),
];

void main() {
  group('AgentDogfoodHarness constructor', () {
    test('rejects non-positive maxTurns and maxTurnBudgetMs', () {
      expect(
        () => AgentDogfoodHarness(
          vm: _HangingVmService(),
          isolateId: 'isolate-0',
          swiftInferConfig: _config,
          goal: 'g',
          tools: _tools,
          fixture: ObservationFixture.empty(),
          maxTurns: 0,
          maxTurnBudgetMs: 100,
          traceSink: _MemorySink(),
          tracePath: '<memory>',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => AgentDogfoodHarness(
          vm: _HangingVmService(),
          isolateId: 'isolate-0',
          swiftInferConfig: _config,
          goal: 'g',
          tools: _tools,
          fixture: ObservationFixture.empty(),
          maxTurns: 1,
          maxTurnBudgetMs: 0,
          traceSink: _MemorySink(),
          tracePath: '<memory>',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AgentDogfoodHarness.run()', () {
    test('budgetExceeded on hanging VmService within total budget',
        () async {
      final sink = _MemorySink();
      final harness = AgentDogfoodHarness(
        vm: _HangingVmService(),
        isolateId: 'isolate-0',
        swiftInferConfig: _config,
        goal: 'turn on dark mode',
        tools: _tools,
        fixture: ObservationFixture.empty(),
        maxTurns: 1,
        // Small budget keeps the test wall-clock-bounded; total budget
        // is 50ms + 5s slack = ~5.05s.
        maxTurnBudgetMs: 50,
        traceSink: sink,
        tracePath: '<memory>',
      );

      final sw = Stopwatch()..start();
      final DogfoodRunResult r = await harness.run();
      sw.stop();

      expect(r.outcome, DogfoodOutcome.budgetExceeded);
      expect(r.toolCallCount, 0);
      expect(r.turnCount, 1);
      expect(r.tracePath, '<memory>');
      expect(r.exception, isNotNull);
      expect(sw.elapsed.inSeconds, lessThan(20));
      // The trace must contain a header and a footer; the footer
      // carries the outcome name.
      expect(sink.lines.any((String l) => l.contains('dogfood_header')),
          isTrue);
      expect(
        sink.lines.any(
          (String l) =>
              l.contains('dogfood_footer') &&
              l.contains(DogfoodOutcome.budgetExceeded.name),
        ),
        isTrue,
      );
      expect(sink.closed, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('typedException when handshake rejects (BindingNotInitialized)',
        () async {
      final sink = _MemorySink();
      final harness = AgentDogfoodHarness(
        vm: _RejectingVmService(),
        isolateId: 'isolate-0',
        swiftInferConfig: _config,
        goal: 'g',
        tools: _tools,
        fixture: ObservationFixture.empty(),
        maxTurns: 1,
        maxTurnBudgetMs: 100,
        traceSink: sink,
        tracePath: '<memory>',
      );

      final DogfoodRunResult r = await harness.run();

      expect(r.outcome, DogfoodOutcome.typedException);
      expect(r.exception, isA<BindingNotInitializedError>());
      expect(r.toolCallCount, 0);
      expect(r.turnCount, 1);
      expect(r.tracePath, '<memory>');
      expect(
        sink.lines.any(
          (String l) =>
              l.contains('dogfood_footer') &&
              l.contains(DogfoodOutcome.typedException.name),
        ),
        isTrue,
      );
    });

    test('failed turn does not mask original error with StateError',
        () async {
      // Regression for lenny-cx6.44: when LoopDriver.runTurn enters its
      // failure branch and writes through its own TrajectoryWriter, the
      // header invariant used to trip with
      // `StateError: writeHeader must precede turns/events`, masking the
      // original turn failure. The fix is to writeHeader on the
      // discardWriter before driver.runSession starts.
      final sink = _MemorySink();
      final harness = AgentDogfoodHarness(
        vm: _HandshakeOkThenHangingVmService(),
        isolateId: 'isolate-0',
        swiftInferConfig: _config,
        goal: 'g',
        tools: _tools,
        fixture: ObservationFixture.empty(),
        maxTurns: 1,
        maxTurnBudgetMs: 50,
        traceSink: sink,
        tracePath: '<memory>',
      );

      final DogfoodRunResult r = await harness.run();

      expect(r.exception, isNot(isA<StateError>()));
      // No trace line carries the historic StateError message.
      expect(
        sink.lines.every(
          (String l) => !l.contains('writeHeader must precede'),
        ),
        isTrue,
        reason: 'no trace line may carry the historic header-invariant '
            'StateError; got: ${sink.lines}',
      );
      // The harness still surfaces a meaningful outcome (the per-turn /
      // session budget trips because the VmService hangs after the
      // handshake).
      expect(
        r.outcome,
        anyOf(
          DogfoodOutcome.budgetExceeded,
          DogfoodOutcome.typedException,
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('DogfoodRunResult exposes all four typed fields', () async {
      final sink = _MemorySink();
      final harness = AgentDogfoodHarness(
        vm: _RejectingVmService(),
        isolateId: 'isolate-0',
        swiftInferConfig: _config,
        goal: 'g',
        tools: _tools,
        fixture: ObservationFixture.empty(),
        maxTurns: 3,
        maxTurnBudgetMs: 50,
        traceSink: sink,
        tracePath: '/tmp/x.jsonl',
      );
      final DogfoodRunResult r = await harness.run();
      expect(r.outcome, isA<DogfoodOutcome>());
      expect(r.tracePath, '/tmp/x.jsonl');
      expect(r.turnCount, 3);
      expect(r.toolCallCount, isA<int>());
      expect(r.exception, isNotNull);
    });
  });

  group('ObservationFixture', () {
    test('missing file throws DogfoodConfigError', () async {
      await expectLater(
        ObservationFixture.loadFromFile('/definitely/does/not/exist.json'),
        throwsA(isA<DogfoodConfigError>()),
      );
    });
  });
}
