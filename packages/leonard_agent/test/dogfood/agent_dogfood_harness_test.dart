/// Unit tests for [AgentDogfoodHarness] (bead lenny-cx6.43, step 5).
///
/// These tests do NOT exercise swift-infer — that is the role of
/// `test/e2e/dogfood_e2e_test.dart`. Here we wire stub `VmService`s to
/// drive the harness through its two non-happy outcomes
/// (budgetExceeded, typedException) and assert the typed result shape.
library;

import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart'
    show BindingNotInitializedError, TrajectorySink;
import 'package:leonard_agent/src/dogfood/agent_dogfood_harness.dart';
import 'package:leonard_agent/src/dogfood/observation_fixture.dart';
import 'package:leonard_agent/src/dogfood/trace_writer.dart';
import 'package:leonard_agent/src/dogfood/types.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_config.dart';
import 'package:leonard_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:leonard_agent/src/trajectory/records.dart'
    show ExtensionManifestRecord, SessionHeader, TurnRecord;
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
/// (which calls `ext.exploration.core.handshake`) and into
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
    if (method == 'ext.exploration.core.handshake') {
      return Future<Response>.value(
        Response.parse(<String, dynamic>{
          'type': 'Response',
          'protocolVersion': '2',
          'extensions': <dynamic>[],
        })!,
      );
    }
    final Completer<Response> c = Completer<Response>();
    return c.future; // hang
  }

  @override
  Future<void> dispose() async {}
}

/// VmService that succeeds on handshake then throws an `RPCError`
/// with a transport code (-32000) on every subsequent call. The
/// `DefaultLoopHost` translates transport-coded RPCErrors into
/// [VmServiceConnectionLost], which the LoopDriver then turns into a
/// `harnessError = connectionLost` termination. Used to assert the
/// harness surfaces the HarnessError name in both
/// `DogfoodRunResult.exception` and the JSONL footer's
/// `exception`/`harness_error` fields (lenny-cx6.45).
class _HandshakeOkThenTransportRpcErrorVmService extends VmService {
  _HandshakeOkThenTransportRpcErrorVmService()
    : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    if (method == 'ext.exploration.core.handshake') {
      return Response.parse(<String, dynamic>{
        'type': 'Response',
        'protocolVersion': '2',
        'extensions': <dynamic>[],
      })!;
    }
    throw RPCError(method, -32000, 'connection closed');
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
    test(
      'budgetExceeded on hanging VmService within total budget',
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
        expect(
          sink.lines.any((String l) => l.contains('dogfood_header')),
          isTrue,
        );
        expect(
          sink.lines.any(
            (String l) =>
                l.contains('dogfood_footer') &&
                l.contains(DogfoodOutcome.budgetExceeded.name),
          ),
          isTrue,
        );
        expect(sink.closed, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'typedException when handshake rejects (BindingNotInitialized)',
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
      },
    );

    test(
      'failed turn does not mask original error with StateError',
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
          reason:
              'no trace line may carry the historic header-invariant '
              'StateError; got: ${sink.lines}',
        );
        // The harness still surfaces a meaningful outcome (the per-turn /
        // session budget trips because the VmService hangs after the
        // handshake).
        expect(
          r.outcome,
          anyOf(DogfoodOutcome.budgetExceeded, DogfoodOutcome.typedException),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('harnessError termination surfaces exception text and harness_error '
        'footer field', () async {
      // Regression for lenny-cx6.45: when the LoopDriver returns a
      // typed `harnessError`-shaped SessionTermination (rather than
      // throwing), the harness must synthesize a sentinel exception so
      // `DogfoodRunResult.exception` and the JSONL footer's `exception`
      // field both carry the HarnessError name. The new `harness_error`
      // footer field additionally carries the wire-name enum value.
      final sink = _MemorySink();
      final harness = AgentDogfoodHarness(
        vm: _HandshakeOkThenTransportRpcErrorVmService(),
        isolateId: 'isolate-0',
        swiftInferConfig: _config,
        goal: 'g',
        tools: _tools,
        fixture: ObservationFixture.empty(),
        maxTurns: 1,
        maxTurnBudgetMs: 1000,
        traceSink: sink,
        tracePath: '<memory>',
      );

      final DogfoodRunResult r = await harness.run();

      expect(r.outcome, DogfoodOutcome.typedException);
      expect(r.exception, isNotNull);
      expect(r.exception!.toString(), contains('connectionLost'));

      final String footer = sink.lines.firstWhere(
        (String l) => l.contains('dogfood_footer'),
        orElse: () => fail(
          'expected a dogfood_footer line; got '
          '${sink.lines}',
        ),
      );
      final Map<String, dynamic> f = jsonDecode(footer) as Map<String, dynamic>;
      expect(f['exception'], isA<String>());
      expect(f['exception'] as String, contains('connectionLost'));
      expect(f['harness_error'], 'connection_lost');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'dogfood_turn line emitted on turn_timeout failed-turn path',
      () async {
        // Regression for lenny-cx6.47: the harness must call
        // DogfoodTraceWriter.writeTurn for every LoopDriver turn — even
        // failed turns. _HandshakeOkThenHangingVmService lets the
        // handshake succeed and then hangs every subsequent call. The
        // LoopDriver's per-turn budget (50ms) fires TurnTimeoutError,
        // which the driver writes to its TrajectoryWriter via the
        // _writeFailedTurn path. Our intercepting writer must surface
        // that turn as a dogfood_turn JSONL line.
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

        await harness.run();

        final List<Map<String, dynamic>> turns = sink.lines
            .map((String l) => jsonDecode(l) as Map<String, dynamic>)
            .where((Map<String, dynamic> j) => j['type'] == 'dogfood_turn')
            .toList();
        expect(
          turns,
          isNotEmpty,
          reason:
              'expected at least one dogfood_turn line on a '
              'failed-turn path; got ${sink.lines}',
        );
        final Map<String, dynamic> first = turns.first;
        expect(first['type'], 'dogfood_turn');
        expect(first['index'], 0);
        expect(first['error'], 'turn_timeout');
        expect(first['elapsed_ms'], isA<int>());
        expect(first['elapsed_ms'] as int, greaterThanOrEqualTo(0));

        final Map<String, dynamic> decision = (first['decision'] as Map)
            .cast<String, dynamic>();
        expect(decision.containsKey('tool'), isTrue);
        expect(decision.containsKey('args'), isTrue);
        expect(decision.containsKey('thinking_excerpt'), isTrue);
        expect(
          (decision['thinking_excerpt'] as String).length,
          lessThanOrEqualTo(2000),
        );
        // observation_summary may be null on the failed-turn path
        // (the LoopDriver's _writeFailedTurn writes _prev.toJson()
        // which is an empty Observation map on the first turn).
        expect(decision.containsKey('observation_summary'), isTrue);

        final Map<String, dynamic> act = (first['act_result'] as Map)
            .cast<String, dynamic>();
        expect(act['ok'], false);
        expect(act['error'], 'turn_timeout');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'dogfood_turn line absent when no turn ever completes',
      () async {
        // Counterpart to the above: _HangingVmService hangs the
        // handshake itself, so the harness exits via the total-run
        // TimeoutException before any LoopDriver turn writes through
        // the interceptor. The trace must carry header + footer and
        // zero dogfood_turn lines.
        final sink = _MemorySink();
        final harness = AgentDogfoodHarness(
          vm: _HangingVmService(),
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
        await harness.run();
        final int turnCount = sink.lines
            .where((String l) => l.contains('"dogfood_turn"'))
            .length;
        expect(
          turnCount,
          0,
          reason:
              'no LoopDriver turn ever wrote; expected zero '
              'dogfood_turn lines, got ${sink.lines}',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'verbose mode logs one [dogfood] turn line per dogfood_turn',
      () async {
        // AC9: when verbose is true, the harness emits a one-line
        // summary per turn via the _log callback, in addition to the
        // JSONL record.
        final sink = _MemorySink();
        final List<String> captured = <String>[];
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
          verbose: true,
          log: captured.add,
        );
        await harness.run();
        final RegExp turnLine = RegExp(
          r'^\[dogfood\] turn 0 tool=.* ok=false ms=-?\d+',
        );
        expect(
          captured.any((String l) => turnLine.hasMatch(l)),
          isTrue,
          reason:
              'expected a "[dogfood] turn 0 ..." log line in '
              'verbose mode; captured=$captured',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

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

  group('dogfood_turn.decision.provider_request_id', () {
    // The harness has no http.Client/provider injection seam (see
    // observation_fixture_e2e_test.dart for the rationale), so a
    // successful turn cannot be driven through `run()` without a real
    // swift-infer. We use the `@visibleForTesting` interceptor factory
    // exposed at the bottom of agent_dogfood_harness.dart to drive the
    // exact same writer the harness wires into the LoopDriver — proving
    // that a TurnRecord carrying providerRequestId surfaces on the
    // dogfood_turn.decision wire shape (lenny-9am AC6).

    TurnRecord buildTurn({String? providerRequestId}) => TurnRecord(
      index: 0,
      observation: const <String, dynamic>{},
      stability: const <String, dynamic>{},
      proposedAction: const <String, dynamic>{
        'tool': 'core.tap',
        'args': <String, dynamic>{'node_id': 7},
      },
      validation: const <String, dynamic>{'ok': true},
      executedAction: const <String, dynamic>{
        'tool': 'core.tap',
        'args': <String, dynamic>{'node_id': 7},
        'result': <String, dynamic>{'ok': true},
      },
      diff: const <String, dynamic>{},
      modelMetadata: const <String, dynamic>{},
      providerRequestId: providerRequestId,
    );

    test('includes provider_request_id when TurnRecord carries it', () async {
      final sink = _MemorySink();
      final trace = DogfoodTraceWriter(sink, '<memory>');
      await trace.writeHeader(goal: 'g', model: 'qwen3.6', tools: _tools);
      final writer = debugDogfoodInterceptingTrajectoryWriterForTesting(
        trace: trace,
        clock: DateTime.now,
      );
      // The interceptor's super-class enforces header invariants on its
      // own (discard) writer.
      await writer.writeHeader(
        const SessionHeader(
          goal: 'g',
          agentsMdHash: '',
          buildIdentifier: 'test',
          modelIdentifier: 'qwen3.6',
          harnessVersion: 'test',
          plugins: <ExtensionManifestRecord>[],
          config: <String, dynamic>{},
        ),
      );
      await writer.writeTurn(buildTurn(providerRequestId: 'msg_test_1'));

      final Map<String, dynamic> turn = sink.lines
          .map((String l) => jsonDecode(l) as Map<String, dynamic>)
          .firstWhere((Map<String, dynamic> j) => j['type'] == 'dogfood_turn');
      final Map<String, dynamic> decision = (turn['decision'] as Map)
          .cast<String, dynamic>();
      expect(decision['provider_request_id'], 'msg_test_1');
    });

    test('omits provider_request_id when TurnRecord leaves it null', () async {
      final sink = _MemorySink();
      final trace = DogfoodTraceWriter(sink, '<memory>');
      await trace.writeHeader(goal: 'g', model: 'qwen3.6', tools: _tools);
      final writer = debugDogfoodInterceptingTrajectoryWriterForTesting(
        trace: trace,
        clock: DateTime.now,
      );
      await writer.writeHeader(
        const SessionHeader(
          goal: 'g',
          agentsMdHash: '',
          buildIdentifier: 'test',
          modelIdentifier: 'qwen3.6',
          harnessVersion: 'test',
          plugins: <ExtensionManifestRecord>[],
          config: <String, dynamic>{},
        ),
      );
      await writer.writeTurn(buildTurn());

      final Map<String, dynamic> turn = sink.lines
          .map((String l) => jsonDecode(l) as Map<String, dynamic>)
          .firstWhere((Map<String, dynamic> j) => j['type'] == 'dogfood_turn');
      final Map<String, dynamic> decision = (turn['decision'] as Map)
          .cast<String, dynamic>();
      expect(decision.containsKey('provider_request_id'), isFalse);
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
