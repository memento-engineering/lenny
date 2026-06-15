/// Library entrypoint for the agent dogfood harness
/// (bead lenny-cx6.43).
///
/// Construction takes a caller-supplied [VmService] (the test wires it
/// to a `BindingVmServiceFake` from `test/_support/`; the CLI does the
/// same), a [SwiftInferConfig], the goal text, the tool descriptors
/// the model can call, an [ObservationFixture], wall-clock budgets,
/// and a [TrajectorySink] receiving the dogfood JSONL trace records.
///
/// The harness drives one full [LoopDriver] session via a [LoopHost]
/// that wraps [DefaultLoopHost] in a [CountingLoopHost] (so the
/// returned [DogfoodRunResult.toolCallCount] is exact). Outcome
/// classification surfaces the four [DogfoodOutcome] values.
///
/// Flutter-binding-agnostic: this file MUST NOT import
/// `package:leonard_flutter` or `package:flutter_test`. The
/// caller owns binding wiring (the CLI boots a real
/// [LeonardBinding]; the e2e test does the same in `setUpAll`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' show VmService;

import '../loop_driver/loop_driver.dart';
import '../loop_driver/loop_host.dart';
import '../loop_driver/types.dart';
import '../session_bringup.dart' show bringUpSession;
import '../prompt/conversation_builder.dart';
import '../loop_driver/default_loop_host.dart';
import '../provider/swift_infer/swift_infer_config.dart';
import '../provider/swift_infer/swift_infer_provider.dart';
import '../provider/types.dart';
import '../session/turn_event.dart';
import '../trajectory/records.dart'
    show
        ExtensionDisabledEvent,
        SessionFooter,
        SessionHeader,
        SessionOutcome,
        TurnRecord;
import '../session.dart';
import '../session/observation_puller.dart' show StabilityPolicy;
import '../trajectory/sink.dart';
import '../trajectory/writer.dart';
import '../types.dart' show LeonardConfig;
import '../validation/action_validator.dart';
import 'counting_host.dart';
import 'observation_fixture.dart';
import 'trace_writer.dart';
import 'types.dart';

/// In-memory [TrajectorySink] that discards lines. The harness uses
/// this internally for the [TrajectoryWriter] handed to [LoopDriver]
/// — the dogfood-specific trace is written separately via
/// [DogfoodTraceWriter] on the caller-supplied sink.
class _DiscardSink implements TrajectorySink {
  @override
  Future<void> writeLine(String line) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

/// File-private sentinel surfacing the [HarnessError] sub-classification
/// from a normally-returned `SessionTermination` (i.e. no Dart exception
/// was thrown — the LoopDriver returned a typed termination). The
/// harness wraps such a termination in this object so the
/// `dogfood_footer.exception` field carries a human-readable string
/// instead of `null`, mirroring how thrown exceptions surface
/// (lenny-cx6.45).
class _HarnessTerminationException implements Exception {
  _HarnessTerminationException(this.harnessError);

  /// The driver-reported sub-classification (e.g. `connectionLost`,
  /// `agentStuck`).
  final HarnessError harnessError;

  @override
  String toString() =>
      'HarnessError.${harnessError.name} (${harnessError.wireName})';
}

/// Drives one exploration session against swift-infer for prompt
/// tuning and CI regression gating. See the bead description and the
/// `tool/agent_dogfood.dart` CLI for usage.
class AgentDogfoodHarness {
  AgentDogfoodHarness({
    required this.vm,
    required this.isolateId,
    required this.swiftInferConfig,
    required this.goal,
    required this.tools,
    required this.fixture,
    required this.maxTurns,
    required this.maxTurnBudgetMs,
    required this.traceSink,
    required this.tracePath,
    this.verbose = false,
    void Function(String)? log,
  }) : _log = log ?? ((_) {}),
       assert(maxTurns > 0, 'maxTurns must be > 0'),
       assert(maxTurnBudgetMs > 0, 'maxTurnBudgetMs must be > 0');

  /// Caller-supplied [VmService]. The CLI and e2e test each wire a
  /// `BindingVmServiceFake` here.
  final VmService vm;

  /// Isolate id passed to [LeonardSession.fromVmService].
  final String isolateId;

  /// Provider configuration (base URL, model, sampling).
  final SwiftInferConfig swiftInferConfig;

  /// Run goal — inserted into the system prompt by the assembler.
  final String goal;

  /// Tool descriptors offered to the model on every turn.
  final List<ToolDescriptor> tools;

  /// Canned observation served by the binding fake on every
  /// `core.get_stable_observation` call. The caller is expected to
  /// construct its `BindingVmServiceFake` with
  /// `observationFixture: fixture` (the CLI runner does this; the
  /// e2e test does the same). The fixture body is wrapped in the
  /// binding's standard `{type: 'Observation', value: <body>}`
  /// envelope before being returned to the agent (lenny-cx6.48).
  final ObservationFixture fixture;

  /// Hard cap on loop iterations.
  final int maxTurns;

  /// Per-turn wall-clock budget in milliseconds. Total run budget is
  /// `maxTurns * maxTurnBudgetMs + 5000ms` slack.
  final int maxTurnBudgetMs;

  /// JSONL sink receiving dogfood header / turn / footer records.
  final TrajectorySink traceSink;

  /// Diagnostic path string echoed back in [DogfoodRunResult.tracePath].
  final String tracePath;

  /// When `true`, emit structured per-turn log lines to [log].
  final bool verbose;

  final void Function(String) _log;

  /// Drive one full session. Returns a typed [DogfoodRunResult]
  /// classifying the outcome. Never re-throws — all typed exceptions
  /// surface via [DogfoodRunResult.outcome] = [DogfoodOutcome.typedException].
  Future<DogfoodRunResult> run() async {
    final DogfoodTraceWriter trace = DogfoodTraceWriter(traceSink, tracePath);
    await trace.writeHeader(
      goal: goal,
      model: swiftInferConfig.model,
      tools: tools,
    );
    if (verbose) {
      _log(
        '[dogfood] start goal="$goal" '
        'model=${swiftInferConfig.model} '
        'tools=${tools.map((ToolDescriptor t) => t.name).toList()} '
        'fixture=${fixture.path} '
        'maxTurns=$maxTurns turnBudgetMs=$maxTurnBudgetMs',
      );
    }

    final SwiftInferModelProvider provider = SwiftInferModelProvider(
      config: swiftInferConfig,
    );
    final LeonardSession session = LeonardSession.fromVmService(vm, isolateId);
    int toolCallCount = 0;
    DogfoodOutcome outcome = DogfoodOutcome.completedNoToolCall;
    Object? capturedException;

    final Duration totalBudget = Duration(
      milliseconds: maxTurns * maxTurnBudgetMs + 5000,
    );

    try {
      await session.start(goal, const LeonardConfig()).timeout(totalBudget);
      final (:header, :host) = await bringUpSession(
        session: session,
        goal: goal,
        policy: StabilityPolicy.actionRelative,
        modelIdentifier: swiftInferConfig.model,
        buildIdentifier: 'dogfood-harness',
        harnessVersion: 'dogfood',
        coreTools: tools,
        extensionTools: const <String, List<ToolDescriptor>>{},
        agentsMd: '',
        extraConfig: <String, dynamic>{
          'max_turns': maxTurns,
          'max_turn_budget_ms': maxTurnBudgetMs,
        },
      );
      final CountingLoopHost countingHost = CountingLoopHost(host);

      // The harness owns its own LoopDriver so we can tune the
      // per-turn budget and the maxTurns cap. We wrap a discard-sink
      // [TrajectoryWriter] in [_DogfoodInterceptingTrajectoryWriter]
      // so every `writeTurn(TurnRecord)` from the loop driver also
      // emits a `dogfood_turn` JSONL line on the caller-supplied sink
      // via [DogfoodTraceWriter]. lenny-cx6.47.
      final _ThinkingAccumulator thinking = _ThinkingAccumulator();
      final _DogfoodInterceptingTrajectoryWriter interceptor =
          _DogfoodInterceptingTrajectoryWriter(
            inner: TrajectoryWriter(_DiscardSink()),
            trace: trace,
            thinking: thinking,
            verbose: verbose,
            log: _log,
            clock: () => DateTime.now(),
          );
      // The LoopDriver's TrajectoryWriter enforces `header → turns* →
      // footer`. If `runTurn` enters its `_writeFailedTurn` branch
      // (TurnTimeoutError / InvalidActionExhausted / SchemaExhausted)
      // before any successful turn lands a header, the invariant trips
      // with `StateError: writeHeader must precede turns/events`,
      // masking the original failure. Write a degenerate header on the
      // interceptor here so the invariant is satisfied trivially — the
      // bytes go to `_DiscardSink` (and the interceptor does NOT emit
      // a dogfood line for header writes; dogfood_header was already
      // written above).
      await interceptor.writeHeader(header);
      final LoopDriver driver = LoopDriver(
        host: countingHost,
        provider: provider,
        conversation: ConversationBuilder(
          systemMessage:
              '${countingHost.agentsMd}\n\n## Goal\n${countingHost.goal}',
          tools: countingHost.mergedTools(),
        ),
        validator: const ActionValidator(),
        writer: interceptor,
        turnBudget: Duration(milliseconds: maxTurnBudgetMs),
        sessionBudget: totalBudget,
        maxTurns: maxTurns,
        onTurnEvent: thinking.onTurnEvent,
      );

      final SessionTermination term = await driver.runSession().timeout(
        totalBudget,
        onTimeout: () {
          return const SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.agentStuck,
          );
        },
      );

      // When the LoopDriver returns a typed `harnessError`-shaped
      // termination, no Dart exception is thrown — the driver returns
      // a `SessionTermination` value. Synthesize a sentinel so the
      // footer's `exception` field is populated (parallel to the
      // thrown-exception paths below) and the run's
      // `DogfoodRunResult.exception` carries the same text. The
      // termination's `harnessError` wire name is threaded into the
      // footer's `harness_error` field separately. lenny-cx6.45.
      if (term.harnessError != null) {
        capturedException = _HarnessTerminationException(term.harnessError!);
      }

      toolCallCount = countingHost.toolCallCount;
      outcome = _classify(term, toolCallCount);
      if (verbose) {
        _log(
          '[dogfood] end outcome=${outcome.name} '
          'toolCalls=$toolCallCount termination=$term',
        );
      }
    } on SchemaRejection catch (e, st) {
      outcome = DogfoodOutcome.typedException;
      capturedException = e;
      if (verbose) {
        _log('[dogfood] SchemaRejection: $e');
      } else {
        _log('[dogfood] FAIL SchemaRejection: $e\n$st');
      }
    } on TurnTimeoutError catch (e) {
      outcome = DogfoodOutcome.budgetExceeded;
      capturedException = e;
      if (verbose) _log('[dogfood] TurnTimeoutError: $e');
    } on TimeoutException catch (e) {
      outcome = DogfoodOutcome.budgetExceeded;
      capturedException = e;
      if (verbose) _log('[dogfood] TimeoutException: $e');
    } catch (e, st) {
      // Unexpected agent exceptions still surface as typedException
      // (e.g. BindingNotInitializedError, ArgumentError from
      // validators). The caller's exception field carries the typed
      // object for downstream introspection.
      outcome = DogfoodOutcome.typedException;
      capturedException = e;
      _log('[dogfood] FAIL ${e.runtimeType}: $e\n$st');
    } finally {
      try {
        await session.end();
      } catch (_) {
        // Best-effort cleanup. Swallow to keep the harness contract
        // (never re-throw) intact.
      }
      // Footer write is the last diagnostic surface for a failed run.
      // If the writer itself throws (defensive: today's writer cannot,
      // but a future regression / injected writer could), the
      // **original** exception must not be displaced by the secondary
      // recovery error. Attempt a second footer write that carries
      // both fields. If even that fails, the original [capturedException]
      // is still surfaced through [DogfoodRunResult.exception] below.
      //
      // When the captured exception is a [_HarnessTerminationException]
      // (the LoopDriver returned a typed `harnessError` termination
      // rather than throwing), surface the wire name on the
      // `harness_error` footer field so post-mortem filtering can
      // bucket by enum value (lenny-cx6.45).
      String? harnessErrorWire;
      final Object? exc = capturedException;
      if (exc is _HarnessTerminationException) {
        harnessErrorWire = exc.harnessError.wireName;
      }
      try {
        await trace.writeFooter(
          outcome: outcome.name,
          exception: capturedException?.toString(),
          harnessError: harnessErrorWire,
        );
      } catch (e) {
        try {
          await trace.writeFooter(
            outcome: outcome.name,
            exception: capturedException?.toString(),
            harnessError: harnessErrorWire,
            recoveryError: e.toString(),
          );
        } catch (_) {
          // Nothing more to do — [capturedException] is still on the
          // returned [DogfoodRunResult] so the caller is not blind.
        }
      }
    }

    return DogfoodRunResult(
      outcome: outcome,
      tracePath: tracePath,
      turnCount: maxTurns,
      toolCallCount: toolCallCount,
      exception: capturedException,
    );
  }

  // Implementation note: the file-private classes
  // [_ThinkingAccumulator], [_DogfoodInterceptingTrajectoryWriter], and
  // [_NoopSink] live below the class declaration (lenny-cx6.47).

  DogfoodOutcome _classify(SessionTermination t, int toolCalls) {
    if (t.harnessError == HarnessError.connectionLost) {
      return DogfoodOutcome.typedException;
    }
    if (t.outcome == SessionOutcome.budgetExhausted) {
      return toolCalls > 0
          ? DogfoodOutcome.completedWithToolCall
          : DogfoodOutcome.budgetExceeded;
    }
    if (t.outcome == SessionOutcome.harnessError) {
      // agent_stuck — three consecutive failed turns. Surface as
      // typedException so the test/CLI sees a non-zero outcome.
      return DogfoodOutcome.typedException;
    }
    return toolCalls > 0
        ? DogfoodOutcome.completedWithToolCall
        : DogfoodOutcome.completedNoToolCall;
  }
}

/// Buckets [TurnThinking] deltas by turn index and surfaces a
/// truncated excerpt on demand. Cleared on read so each
/// [DogfoodTraceWriter.writeTurn] consumes only its own deltas.
/// File-private to the dogfood harness (lenny-cx6.47).
class _ThinkingAccumulator {
  final Map<int, StringBuffer> _byTurn = <int, StringBuffer>{};

  void onTurnEvent(TurnEvent e) {
    if (e is TurnThinking) {
      (_byTurn[e.turn] ??= StringBuffer()).write(e.delta.text);
    }
  }

  /// Returns the accumulated thinking text for [turn], truncated to
  /// [maxLen] characters (default 2000). Clears the bucket so any
  /// subsequent read (e.g. a defensive retry of `writeTurn`) returns
  /// the empty string.
  String drain(int turn, {int maxLen = 2000}) {
    final StringBuffer? b = _byTurn.remove(turn);
    if (b == null) return '';
    final String s = b.toString();
    return s.length <= maxLen ? s : s.substring(0, maxLen);
  }
}

/// Subclasses [TrajectoryWriter] so the LoopDriver's writer
/// invariants (`header → turns* → footer`) stay unchanged. For every
/// `writeTurn(TurnRecord)` call we additionally emit one
/// `dogfood_turn` line on the caller-supplied [DogfoodTraceWriter].
/// File-private to the dogfood harness (lenny-cx6.47); a
/// `@visibleForTesting` factory under [DogfoodInterceptingWriterForTesting]
/// at the bottom of this file lets unit tests assert the JSONL shape
/// without driving the full harness — used by lenny-9am to lock the
/// `provider_request_id` decision-map plumbing end to end.
class _DogfoodInterceptingTrajectoryWriter extends TrajectoryWriter {
  _DogfoodInterceptingTrajectoryWriter({
    required TrajectoryWriter inner,
    required this.trace,
    required this.thinking,
    required this.verbose,
    required this.log,
    required this.clock,
  }) : _inner = inner,
       super(_NoopSink()) {
    _turnStart = clock();
  }

  final TrajectoryWriter _inner;
  final DogfoodTraceWriter trace;
  final _ThinkingAccumulator thinking;
  final bool verbose;
  final void Function(String) log;
  final DateTime Function() clock;
  late DateTime _turnStart;

  @override
  Future<void> writeHeader(SessionHeader h) async {
    await _inner.writeHeader(h);
    _turnStart = clock();
  }

  @override
  Future<void> writeTurn(TurnRecord t) async {
    await _inner.writeTurn(t);
    final DateTime now = clock();
    final int elapsedMs = now.difference(_turnStart).inMilliseconds;
    _turnStart = now;

    final Map<String, dynamic> exec = t.executedAction;
    final Map<String, dynamic> val = t.validation;
    final bool ok = val['ok'] == true;
    final String tool =
        (exec['tool'] as String?) ??
        (t.proposedAction['tool'] as String?) ??
        '';
    final Map<String, dynamic> args =
        (exec['args'] as Map?)?.cast<String, dynamic>() ??
        (t.proposedAction['args'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final Map<String, dynamic>? result = (exec['result'] as Map?)
        ?.cast<String, dynamic>();

    final Map<String, dynamic> decision = <String, dynamic>{
      'tool': tool,
      'args': args,
      'thinking_excerpt': thinking.drain(t.index),
      'observation_summary': _observationSummary(t),
      if (t.providerRequestId != null)
        'provider_request_id': t.providerRequestId,
    };

    final Map<String, dynamic> actResult = ok && result != null
        ? <String, dynamic>{
            'ok': result['ok'] ?? true,
            if (result.containsKey('value')) 'value': result['value'],
            if (result.containsKey('error')) 'error': result['error'],
          }
        : <String, dynamic>{'ok': false, 'error': val['reason'] ?? 'unknown'};

    final String? error = ok ? null : (val['reason'] as String?);

    await trace.writeTurn(
      index: t.index,
      prompt: _summarisePrompt(t),
      decision: decision,
      actResult: actResult,
      elapsedMs: elapsedMs < 0 ? 0 : elapsedMs,
      error: error,
    );

    if (verbose) {
      log(
        '[dogfood] turn ${t.index} tool=$tool ok=$ok ms=$elapsedMs'
        '${error == null ? '' : ' error=$error'}',
      );
    }
  }

  @override
  Future<void> writeExtensionDisabled(ExtensionDisabledEvent e) =>
      _inner.writeExtensionDisabled(e);

  @override
  Future<void> close(SessionFooter footer) => _inner.close(footer);
}

/// Compact, JSON-encodable summary of the observation captured for
/// this turn. Returns `null` when the turn record carries no
/// observation (failed-turn path with an empty `_prev`).
///
/// Wire shape: `Observation.toJson()` serialises `core` as a
/// CoreFragment map with `routeStack` (camelCase `List<String>`) and
/// `nodes` as a `Map<String, dynamic>` keyed by node-id strings — not
/// a List. We count Map entries for node_count.
Map<String, dynamic>? _observationSummary(TurnRecord t) {
  if (t.observation.isEmpty) return null;
  final Map<String, dynamic> obs = t.observation;
  final Map<String, dynamic>? core = (obs['core'] as Map?)
      ?.cast<String, dynamic>();
  final Object? nodesRaw = core?['nodes'];
  final int nodeCount = nodesRaw is Map
      ? nodesRaw.length
      : (nodesRaw is List ? nodesRaw.length : 0);
  final Object? routeRaw = core?['routeStack'] ?? core?['route_stack'];
  final List<dynamic> routeStack = routeRaw is List
      ? List<dynamic>.from(routeRaw)
      : const <dynamic>[];
  return <String, dynamic>{
    'keys': obs.keys.toList()..sort(),
    'node_count': nodeCount,
    'route_stack': routeStack,
  };
}

/// Compact prompt summary: the literal bytes sent to swift-infer are
/// NOT on [TurnRecord] (full-prompt capture is intentionally out of
/// scope for cx6.47). We serialize the observation top-level keys and
/// the per-turn diff so post-mortem readers can see what changed each
/// turn. Truncated to 2000 characters.
String _summarisePrompt(TurnRecord t) {
  final Map<String, dynamic> obs = t.observation;
  final Map<String, dynamic> diff = t.diff;
  final List<String> obsKeys = obs.keys.toList()..sort();
  final String s = jsonEncode(<String, dynamic>{
    'observation_keys': obsKeys,
    'diff_summary': diff,
  });
  return s.length <= 2000 ? s : s.substring(0, 2000);
}

/// Minimal no-op [TrajectorySink] used as the `super(...)` argument
/// for [_DogfoodInterceptingTrajectoryWriter]. The subclass overrides
/// every public method on [TrajectoryWriter], so this sink is never
/// actually written to — it exists only because the base class's
/// constructor requires a non-null sink. We keep it distinct from
/// [_DiscardSink] (which is the inner writer's real sink) so the
/// override contract is obvious to future readers.
class _NoopSink implements TrajectorySink {
  @override
  Future<void> writeLine(String _) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

/// Test-only factory exposing the file-private
/// [_DogfoodInterceptingTrajectoryWriter] as a [TrajectoryWriter]. The
/// harness has no `http.Client` or `ModelProvider` injection seam (see
/// `observation_fixture_e2e_test.dart` for the rationale), so unit
/// tests cannot drive a successful turn through `run()` without a
/// real swift-infer. This entry point lets a unit test construct the
/// interceptor over a [DogfoodTraceWriter] writing to a memory sink
/// and call `writeTurn(TurnRecord(..., providerRequestId: ...))`
/// directly to assert the JSONL `decision.provider_request_id` shape
/// (lenny-9am AC6 end-to-end).
@visibleForTesting
TrajectoryWriter debugDogfoodInterceptingTrajectoryWriterForTesting({
  required DogfoodTraceWriter trace,
  required DateTime Function() clock,
}) => _DogfoodInterceptingTrajectoryWriter(
  inner: TrajectoryWriter(_DiscardSink()),
  trace: trace,
  thinking: _ThinkingAccumulator(),
  verbose: false,
  log: (_) {},
  clock: clock,
);
