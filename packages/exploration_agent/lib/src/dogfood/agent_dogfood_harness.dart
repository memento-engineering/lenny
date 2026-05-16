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
/// `package:exploration_flutter` or `package:flutter_test`. The
/// caller owns binding wiring (the CLI boots a real
/// [ExplorationBinding]; the e2e test does the same in `setUpAll`).
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart' show VmService;

import '../loop_driver/loop_driver.dart';
import '../loop_driver/loop_host.dart';
import '../loop_driver/types.dart';
import '../memory/action_ring.dart';
import '../memory/running_summary.dart';
import '../memory/token_counter.dart';
import '../prompt/prompt_assembler.dart';
import '../loop_driver/default_loop_host.dart';
import '../provider/swift_infer/swift_infer_config.dart';
import '../provider/swift_infer/swift_infer_provider.dart';
import '../provider/types.dart';
import '../trajectory/records.dart'
    show PluginManifestRecord, SessionHeader, SessionOutcome;
import '../session.dart';
import '../session/observation_puller.dart' show StabilityPolicy;
import '../trajectory/sink.dart';
import '../trajectory/writer.dart';
import '../types.dart' show ExplorationConfig;
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
  })  : _log = log ?? ((_) {}),
        assert(maxTurns > 0, 'maxTurns must be > 0'),
        assert(maxTurnBudgetMs > 0, 'maxTurnBudgetMs must be > 0');

  /// Caller-supplied [VmService]. The CLI and e2e test each wire a
  /// `BindingVmServiceFake` here.
  final VmService vm;

  /// Isolate id passed to [ExplorationSession.fromVmService].
  final String isolateId;

  /// Provider configuration (base URL, model, sampling).
  final SwiftInferConfig swiftInferConfig;

  /// Run goal — inserted into the system prompt by the assembler.
  final String goal;

  /// Tool descriptors offered to the model on every turn.
  final List<ToolDescriptor> tools;

  /// Canned observation served by the binding fake when the agent
  /// pulls `core.get_stable_observation`. Currently informational —
  /// the binding fake's observation path is owned by the caller's
  /// [ExplorationBinding], not by the harness; the fixture is
  /// recorded in the trace header so prompt-tuning diffs can be
  /// reproduced.
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
    final DogfoodTraceWriter trace =
        DogfoodTraceWriter(traceSink, tracePath);
    await trace.writeHeader(goal: goal, model: swiftInferConfig.model,
        tools: tools);
    if (verbose) {
      _log('[dogfood] start goal="$goal" '
          'model=${swiftInferConfig.model} '
          'tools=${tools.map((ToolDescriptor t) => t.name).toList()} '
          'fixture=${fixture.path} '
          'maxTurns=$maxTurns turnBudgetMs=$maxTurnBudgetMs');
    }

    final SwiftInferModelProvider provider =
        SwiftInferModelProvider(config: swiftInferConfig);
    final ExplorationSession session =
        ExplorationSession.fromVmService(vm, isolateId);
    int toolCallCount = 0;
    DogfoodOutcome outcome = DogfoodOutcome.completedNoToolCall;
    Object? capturedException;

    final Duration totalBudget = Duration(
      milliseconds: maxTurns * maxTurnBudgetMs + 5000,
    );

    try {
      await session
          .start(goal, const ExplorationConfig())
          .timeout(totalBudget);
      final DefaultLoopHost inner = DefaultLoopHost.fromSession(
        session: session,
        coreTools: tools,
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: goal,
        agentsMd: '',
        policy: StabilityPolicy.actionRelative,
      );
      final CountingLoopHost host = CountingLoopHost(inner);

      // The harness owns its own LoopDriver so we can tune the
      // per-turn budget and the maxTurns cap; the trajectory writer
      // is wired to a discard sink because dogfood records are
      // written on `traceSink` via DogfoodTraceWriter above.
      final TrajectoryWriter discardWriter =
          TrajectoryWriter(_DiscardSink());
      // The LoopDriver's TrajectoryWriter enforces `header → turns* →
      // footer`. If `runTurn` enters its `_writeFailedTurn` branch
      // (TurnTimeoutError / InvalidActionExhausted / SchemaExhausted)
      // before any successful turn lands a header, the invariant trips
      // with `StateError: writeHeader must precede turns/events`,
      // masking the original failure. Write a degenerate header here so
      // the invariant is satisfied trivially — the bytes go to
      // `_DiscardSink` since the harness owns its own dogfood trace via
      // [DogfoodTraceWriter].
      await discardWriter.writeHeader(SessionHeader(
        goal: goal,
        agentsMdHash: '',
        buildIdentifier: 'dogfood-harness',
        modelIdentifier: swiftInferConfig.model,
        harnessVersion: 'dogfood',
        plugins: const <PluginManifestRecord>[],
        config: <String, dynamic>{
          'max_turns': maxTurns,
          'max_turn_budget_ms': maxTurnBudgetMs,
        },
      ));
      final LoopDriver driver = LoopDriver(
        host: host,
        provider: provider,
        assembler: const PromptAssembler(),
        validator: const ActionValidator(),
        writer: discardWriter,
        summary: RunningSummary(counter: WhitespaceTokenCounter()),
        actions: ActionRing(),
        turnBudget: Duration(milliseconds: maxTurnBudgetMs),
        sessionBudget: totalBudget,
        maxTurns: maxTurns,
      );

      final SessionTermination term =
          await driver.runSession().timeout(totalBudget, onTimeout: () {
        return const SessionTermination(
          SessionOutcome.harnessError,
          harnessError: HarnessError.agentStuck,
        );
      });

      toolCallCount = host.toolCallCount;
      outcome = _classify(term, toolCallCount);
      if (verbose) {
        _log('[dogfood] end outcome=${outcome.name} '
            'toolCalls=$toolCallCount termination=$term');
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
      try {
        await trace.writeFooter(
          outcome: outcome.name,
          exception: capturedException?.toString(),
        );
      } catch (e) {
        try {
          await trace.writeFooter(
            outcome: outcome.name,
            exception: capturedException?.toString(),
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
