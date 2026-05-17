/// PRD §10 perception-action loop driver.
///
/// Runs one turn at a time (the canonical 10-step ordering) and a
/// session loop on top with budgets + PRD §17 failure modes:
///
/// 1. stabilize
/// 2. deserialize core fragment
/// 3. deserialize plugin fragments
/// 4. diff
/// 5. build prompt
/// 6. decide
/// 7. validate
/// 8. act
/// 9. notify plugins
/// 10. persist
///
/// The 10-step ordering is load-bearing. Tests assert exact call
/// sequence so future "cleanups" don't reorder steps.
library;

import 'dart:async';

import '../memory/action_ring.dart';
import '../memory/running_summary.dart';
import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../observation/observation_differ.dart';
import '../prompt/prompt_assembler.dart';
import '../provider/types.dart';
import '../provider/action_schema.dart';
import '../provider/model_provider.dart';
import '../session/turn_event.dart';
import '../trajectory/records.dart';
import '../trajectory/writer.dart';
import '../validation/action_validator.dart';
import 'loop_host.dart';
import 'plugin_failure_tracker.dart';
import 'types.dart';
import 'validation_retry.dart';

/// Tool name used by the model to declare voluntary success
/// (PRD §10, cx6.6 core action set).
const String _kCoreDoneTool = 'core.done';

/// Wire string used for the trajectory footer's `outcome` field when
/// the session terminates with [SessionOutcome.budgetExhausted].
const String _kBudgetExhaustedWire = 'budget_exhausted';

/// Default budgets — overridable for tests via [LoopDriver]'s
/// constructor.
const Duration _kDefaultTurnBudget = Duration(seconds: 30);
const Duration _kDefaultSessionBudget = Duration(minutes: 15);
const int _kDefaultMaxTurns = 50;
const int _kMaxConsecutiveFailedTurns = 3;

/// Function returning the current wall-clock time. Tests inject a
/// fake clock to advance the per-session 15-min budget without
/// real-time waits.
typedef Clock = DateTime Function();

class LoopDriver {
  LoopDriver({
    required LoopHost host,
    required ModelProvider provider,
    required PromptAssembler assembler,
    required ActionValidator validator,
    required TrajectoryWriter writer,
    required RunningSummary summary,
    required ActionRing actions,
    Duration turnBudget = _kDefaultTurnBudget,
    Duration sessionBudget = _kDefaultSessionBudget,
    int maxTurns = _kDefaultMaxTurns,
    Clock? clock,
    void Function(TurnEvent)? onTurnEvent,
  })  : _host = host,
        _provider = provider,
        _assembler = assembler,
        _validator = validator,
        _writer = writer,
        _summary = summary,
        _actions = actions,
        _turnBudget = turnBudget,
        _sessionBudget = sessionBudget,
        _maxTurns = maxTurns,
        _clock = clock ?? DateTime.now,
        _onTurnEvent = onTurnEvent;

  final LoopHost _host;
  final ModelProvider _provider;
  final PromptAssembler _assembler;
  final ActionValidator _validator;
  final TrajectoryWriter _writer;
  final RunningSummary _summary;
  final ActionRing _actions;
  final Duration _turnBudget;
  final Duration _sessionBudget;
  final int _maxTurns;
  final Clock _clock;

  /// Optional sink for [TurnEvent]s — wired by `ExplorationSession.run`
  /// to forward thinking deltas, action+validation outcomes, and turn
  /// boundaries to `ExplorationSession.turnEvents`.
  final void Function(TurnEvent)? _onTurnEvent;

  Observation _prev = Observation.empty();
  int _turnIndex = 0;
  int _consecutiveFailedTurns = 0;
  bool _doneRequested = false;
  String? _doneReason;
  DateTime? _sessionStart;

  /// Plugin auto-disable counter (PRD §17, threshold = 3).
  final PluginFailureTracker pluginFailures = PluginFailureTracker();

  // ---- introspection (visible for tests / wiring) ----
  int get turnIndex => _turnIndex;
  int get consecutiveFailedTurns => _consecutiveFailedTurns;
  bool get doneRequested => _doneRequested;
  String? get doneReason => _doneReason;
  Duration get turnBudget => _turnBudget;

  /// Run exactly one turn. PRD §10 ten-step ordering. Returns the
  /// persisted [TurnRecord] on success. On a failed turn (timeout /
  /// validator-exhausted / schema-exhausted) the failed-turn record
  /// has already been written; the call throws [TurnFailure] so the
  /// session loop can count consecutive failures.
  ///
  /// Propagates [VmServiceConnectionLost] unwrapped — the session loop
  /// translates it into a `connection_lost` termination.
  Future<TurnRecord> runTurn() async {
    final int idx = _turnIndex;
    try {
      final TurnRecord r = await _runTurnInner(idx).timeout(
        _turnBudget,
        onTimeout: () => throw TurnTimeoutError(idx),
      );
      _consecutiveFailedTurns = 0;
      _turnIndex++;
      return r;
    } on TurnTimeoutError catch (_) {
      await _writeFailedTurn(idx, reason: 'turn_timeout');
      _emitTurnEvent(TurnValidation(idx, false, 'turn_timeout'));
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _turnIndex++;
      throw TurnFailure(idx, 'turn_timeout');
    } on InvalidActionExhausted catch (e) {
      await _writeFailedTurn(
        idx,
        reason: 'invalid_action_exhausted',
        rejections: e.rejections,
      );
      _emitTurnEvent(
        TurnValidation(idx, false, 'invalid_action_exhausted'),
      );
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _turnIndex++;
      throw TurnFailure(idx, 'invalid_action_exhausted', e);
    } on SchemaExhausted catch (e) {
      await _writeFailedTurn(
        idx,
        reason: 'schema_exhausted',
        schemaError: e.cause.validationError,
      );
      _emitTurnEvent(TurnValidation(idx, false, 'schema_exhausted'));
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _turnIndex++;
      throw TurnFailure(idx, 'schema_exhausted', e);
    }
  }

  Future<TurnRecord> _runTurnInner(int idx) async {
    // step 1+2+3: stabilize + deserialize (core + plugin fragments).
    final Observation curr = await _host.observe();
    await _accountPluginStrikes(curr);

    // step 4: diff against the previous turn's observation.
    final ObservationDiff diff = ObservationDiffer.diff(_prev, curr);

    // step 5: build prompt against the CURRENT merged tool list
    // (auto-disabled plugins already excluded).
    final List<ToolDescriptor> mergedTools = _host.mergedTools();
    final PromptPayload prompt = _assembler.assemble(
      agentsMd: _host.agentsMd,
      goal: _host.goal,
      summary: _summary,
      actionRing: _actions,
      observation: curr,
      diff: diff,
      mergedTools: mergedTools,
    );
    final ActionSchema schema = ActionSchema.fromToolList(mergedTools);

    // Forward provider thinking deltas to the session's turnEvents
    // stream while step 6 (decide) is in flight. The subscription is
    // bounded by the surrounding `_runTurnInner` future via cancel() in
    // the finally block.
    StreamSubscription<ThinkingDelta>? thinkingSub;
    if (_onTurnEvent != null) {
      thinkingSub = _provider.thinking().listen((d) {
        _onTurnEvent(TurnThinking(idx, d));
      });
    }

    final ValidationLoopResult v;
    try {
      // steps 6+7: decide + validate (with retry budgets).
      v = await decideAndValidate(
        provider: _provider,
        basePrompt: prompt,
        schema: schema,
        validator: _validator,
        observation: curr,
        mergedTools: mergedTools,
      );
    } finally {
      await thinkingSub?.cancel();
    }

    // After validate: emit the chosen action + validation outcome.
    _emitTurnEvent(TurnActionDecided(
      idx,
      v.decision.action.tool,
      v.decision.action.args,
    ));
    _emitTurnEvent(TurnValidation(idx, true, null));

    // step 8: act.
    final Map<String, dynamic> exec = await _host.executeAction(
      v.decision.action.tool,
      v.decision.action.args,
    );

    if (v.decision.action.tool == _kCoreDoneTool) {
      _doneRequested = true;
      final Object? rawReason = v.decision.action.args['reason'];
      _doneReason = rawReason is String ? rawReason : null;
    }

    // step 9: notify plugins.
    await _host.notifyPlugins(
      v.decision.action.tool,
      v.decision.action.args,
      exec,
    );

    // step 10: persist.
    final TurnRecord rec = TurnRecord(
      index: idx,
      observation: curr.toJson(),
      stability: curr.stability.toJson(),
      proposedAction: <String, dynamic>{
        'tool': v.decision.action.tool,
        'args': v.decision.action.args,
      },
      validation: <String, dynamic>{
        'ok': true,
        'retries': v.retries,
        if (v.rejections.isNotEmpty) 'rejections': v.rejections,
        if (v.schemaRetries > 0) 'schema_retries': v.schemaRetries,
      },
      executedAction: <String, dynamic>{
        'tool': v.decision.action.tool,
        'args': v.decision.action.args,
        'result': exec,
      },
      diff: diff.toJson(),
      summaryUpdate: v.decision.summaryUpdate ?? '',
      modelMetadata: <String, dynamic>{
        if (v.decision.rationale != null) 'rationale': v.decision.rationale,
        if (v.decision.waitStrategy != null) 'wait_strategy': v.decision.waitStrategy,
      },
      providerRequestId: v.decision.providerRequestId,
    );
    await _writer.writeTurn(rec);

    // post-persist memory updates — failures here don't fail the turn.
    if (v.decision.summaryUpdate != null) {
      try {
        _summary.update(v.decision.summaryUpdate!);
      } on SummaryOversizeError catch (_) {
        // Surface via summary state next turn — see PRD §13.
      }
    }
    _actions.push(_actionLine(v.decision.action.tool, exec));
    _prev = curr;

    // step 10 (cont.): turn boundary marker for downstream consumers.
    _emitTurnEvent(TurnComplete(idx));
    return rec;
  }

  void _emitTurnEvent(TurnEvent e) {
    final cb = _onTurnEvent;
    if (cb != null) cb(e);
  }

  Future<void> _writeFailedTurn(
    int idx, {
    required String reason,
    List<String>? rejections,
    String? schemaError,
  }) async {
    final TurnRecord rec = TurnRecord(
      index: idx,
      observation: _prev.toJson(),
      stability: _prev.stability.toJson(),
      proposedAction: const <String, dynamic>{},
      validation: <String, dynamic>{
        'ok': false,
        'reason': reason,
        if (rejections != null) 'rejections': rejections,
        if (schemaError != null) 'schema_error': schemaError,
      },
      executedAction: const <String, dynamic>{},
      diff: const <String, dynamic>{},
      summaryUpdate: '',
      modelMetadata: const <String, dynamic>{},
    );
    await _writer.writeTurn(rec);
  }

  Future<void> _accountPluginStrikes(Observation curr) async {
    for (final String ns in _host.activePluginNamespaces()) {
      final PluginFragment? frag = curr.plugins[ns];
      // "Success" = fragment is present and reports no error. The
      // binding signals plugin-side errors via an `error` key in the
      // fragment data map (PRD §17 plugin isolation contract).
      final bool ok = frag != null && frag.data['error'] == null;
      if (ok) {
        pluginFailures.recordSuccess(ns);
        continue;
      }
      final bool reachedThreshold = pluginFailures.recordFailure(ns);
      if (reachedThreshold) {
        const String reason =
            'auto_disable: 3 consecutive observation failures';
        _host.disablePlugin(ns, reason);
        await _writer.writePluginDisabled(PluginDisabledEvent(
          namespace: ns,
          reason: reason,
          turn: _turnIndex,
        ));
      }
    }
  }

  String _actionLine(String tool, Map<String, dynamic> result) {
    final Object? ok = result['ok'];
    final String suffix = ok is bool ? (ok ? 'ok' : 'failed') : 'done';
    return '$tool: $suffix';
  }

  // ===== session loop =====

  /// Run a full session. Returns when one of the PRD §17 termination
  /// conditions fires:
  ///   * 50 turns OR 15 minutes wall-clock → `budget_exhausted`
  ///   * 3 consecutive failed turns → `harness_error agent_stuck`
  ///   * VM connection lost mid-turn → `harness_error connection_lost`
  ///   * voluntary `core.done(reason)` → `done`
  ///
  /// On termination the trajectory writer is closed with the final
  /// footer (idempotently). [BindingNotInitializedError] is raised by
  /// `ExplorationSession.start()` (PRD .11) before [runSession] is
  /// invoked, so it is never observed here.
  Future<SessionTermination> runSession() async {
    _sessionStart = _clock();
    SessionTermination? termination;
    try {
      while (true) {
        if (_turnIndex >= _maxTurns ||
            _clock().difference(_sessionStart!) >= _sessionBudget) {
          termination = SessionTermination(SessionOutcome.budgetExhausted);
          return termination;
        }
        if (_consecutiveFailedTurns >= _kMaxConsecutiveFailedTurns) {
          termination = const SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.agentStuck,
          );
          return termination;
        }
        try {
          await runTurn();
          if (_doneRequested) {
            termination = SessionTermination(
              SessionOutcome.done,
              finalSummary: _doneReason,
            );
            return termination;
          }
        } on TurnFailure {
          // counted by runTurn — loop continues.
        } on VmServiceConnectionLost {
          termination = const SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.connectionLost,
          );
          return termination;
        }
      }
    } finally {
      // Close writer with the appropriate footer (close() is
      // idempotent, so duplicate calls are safe if termination is
      // already set).
      final SessionTermination t =
          termination ?? const SessionTermination(SessionOutcome.harnessError);
      await _writer.close(SessionFooter(
        outcome: t.outcome,
        finalSummary: t.finalSummary ?? _summary.text,
        totalTurns: _turnIndex,
        totalDurationMs: _sessionStart == null
            ? 0
            : _clock().difference(_sessionStart!).inMilliseconds,
        harnessError: t.harnessError?.wireName,
      ));
    }
  }

  // Re-export for tests that want to assert the budget-exhausted wire
  // name without importing the trajectory record directly.
  String get budgetExhaustedWireName => _kBudgetExhaustedWire;
}
