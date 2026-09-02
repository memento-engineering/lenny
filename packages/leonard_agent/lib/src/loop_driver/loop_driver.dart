/// PRD §10 perception-action loop driver.
///
/// Runs one turn at a time (the canonical 10-step ordering) and a
/// session loop on top with budgets + PRD §17 failure modes:
///
/// 1. stabilize
/// 2. deserialize core fragment
/// 3. deserialize extension fragments
/// 4. diff
/// 5. build prompt
/// 6. decide
/// 7. validate
/// 8. act
/// 9. notify extensions
/// 10. persist
///
/// The 10-step ordering is load-bearing. Tests assert exact call
/// sequence so future "cleanups" don't reorder steps.
library;

import 'dart:async';

import '../errors.dart';
import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../observation/observation_differ.dart';
import '../prompt/conversation_builder.dart';
import '../provider/action_schema.dart';
import '../provider/model_provider.dart';
import '../provider/types.dart';
import '../session/turn_event.dart';
import '../trajectory/records.dart';
import '../trajectory/writer.dart';
import '../validation/action_validator.dart';
import 'loop_host.dart';
import 'extension_failure_tracker.dart';
import 'provider_transport.dart';
import 'types.dart';
import 'validation_retry.dart';

/// Tool name used by the model to declare voluntary success
/// (PRD §10, core action set).
const String _kCoreDoneTool = 'core.done';

/// Reserved namespace for built-in core actions (tap/enter_text/done/etc.).
/// Core's observation health is carried in [CoreFragment] (curr.core), NOT
/// in curr.extensions['core'] — so core must be exempt from the
/// extension-strike mechanism. Value must match
/// [CoreExtension.namespace] == 'core'
/// (packages/leonard_flutter/lib/src/core_tools/core_extension.dart:87).
const String _kCoreNamespace = 'core';

/// Wire string used for the trajectory footer's `outcome` field when
/// the session terminates with [SessionOutcome.budgetExhausted].
const String _kBudgetExhaustedWire = 'budget_exhausted';

/// Default budgets — overridable for tests via [LoopDriver]'s
/// constructor.
const Duration _kDefaultTurnBudget = Duration(seconds: 120);
const Duration _kDefaultSessionBudget = Duration(minutes: 15);
const int _kDefaultMaxTurns = 50;
const int _kDefaultTokenBudget = 32000;
const int _kMaxConsecutiveFailedTurns = 3;
const int _kMaxConsecutiveTurnTimeouts = 5;

/// Backoff before the turn following a `provider_transport` failure. The wire
/// just died; hammering it immediately burns the 3-failure ladder in
/// milliseconds. Tests inject [Duration.zero].
const Duration _kDefaultProviderRetryBackoff = Duration(seconds: 2);

/// Function returning the current wall-clock time. Tests inject a
/// fake clock to advance the per-session 15-min budget without
/// real-time waits.
typedef Clock = DateTime Function();

class LoopDriver {
  LoopDriver({
    required LoopHost host,
    required ModelProvider provider,
    required ConversationBuilder conversation,
    required ActionValidator validator,
    required TrajectoryWriter writer,
    Duration turnBudget = _kDefaultTurnBudget,
    Duration sessionBudget = _kDefaultSessionBudget,
    int maxTurns = _kDefaultMaxTurns,
    int tokenBudget = _kDefaultTokenBudget,
    Duration providerRetryBackoff = _kDefaultProviderRetryBackoff,
    Clock? clock,
    void Function(TurnEvent)? onTurnEvent,
  }) : _host = host,
       _provider = provider,
       _conversation = conversation,
       _validator = validator,
       _writer = writer,
       _turnBudget = turnBudget,
       _sessionBudget = sessionBudget,
       _maxTurns = maxTurns,
       _tokenBudget = tokenBudget,
       _providerRetryBackoff = providerRetryBackoff,
       _clock = clock ?? DateTime.now,
       _onTurnEvent = onTurnEvent;

  final LoopHost _host;
  final ModelProvider _provider;
  final ConversationBuilder _conversation;
  final ActionValidator _validator;
  final TrajectoryWriter _writer;
  final Duration _turnBudget;
  final Duration _sessionBudget;
  final int _maxTurns;
  final int _tokenBudget;
  final Duration _providerRetryBackoff;
  final Clock _clock;

  /// Optional sink for [TurnEvent]s — wired by `LeonardSession.run`
  /// to forward thinking deltas, action+validation outcomes, and turn
  /// boundaries to `LeonardSession.turnEvents`.
  final void Function(TurnEvent)? _onTurnEvent;

  Observation _prev = Observation.empty();
  int _turnIndex = 0;
  int _consecutiveFailedTurns = 0;
  int _consecutiveTurnTimeouts = 0;
  bool _doneRequested = false;
  String? _doneReason;
  DateTime? _sessionStart;

  /// `provider_request_id` of the most recent SUCCESSFUL decide. Carried into
  /// the `provider_transport` detail so a footer names the request that
  /// preceded the dead stream.
  String? _lastProviderRequestId;

  /// Detail for the most recent failed turn, e.g.
  /// `'provider_transport: ClientException; provider_request_id=req-7'`.
  /// Becomes the footer's `termination_detail` on an `agent_stuck`
  /// termination; cleared by a successful turn.
  String? _lastFailureDetail;

  /// Failed-action carry-forward. When the previous turn's executed
  /// action returned `{ok: false}`, the error map is staged here; the
  /// next turn's [UserTurn] receives it as `toolResult` so the model
  /// sees the structured failure on its next decide call.
  Map<String, dynamic>? _pendingToolResult;

  /// Extension auto-disable counter (PRD §17, threshold = 3).
  final ExtensionFailureTracker extensionFailures = ExtensionFailureTracker();

  // ---- introspection (visible for tests / wiring) ----
  int get turnIndex => _turnIndex;
  int get consecutiveFailedTurns => _consecutiveFailedTurns;
  int get consecutiveTurnTimeouts => _consecutiveTurnTimeouts;
  bool get doneRequested => _doneRequested;
  String? get doneReason => _doneReason;
  Duration get turnBudget => _turnBudget;

  /// Detail of the most recent failed turn, or `null` after a successful one.
  String? get lastFailureDetail => _lastFailureDetail;

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
      final TurnRecord r = await _runTurnInner(
        idx,
      ).timeout(_turnBudget, onTimeout: () => throw TurnTimeoutError(idx));
      _consecutiveFailedTurns = 0;
      _consecutiveTurnTimeouts = 0;
      _lastFailureDetail = null;
      _turnIndex++;
      return r;
    } on TurnTimeoutError catch (_) {
      await _writeFailedTurn(idx, reason: 'turn_timeout');
      _emitTurnEvent(TurnValidation(idx, false, 'turn_timeout'));
      _emitTurnEvent(
        TurnUsage(idx, _conversation.estimatedTokens(), _tokenBudget),
      );
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveTurnTimeouts++;
      _lastFailureDetail = 'turn_timeout';
      _turnIndex++;
      throw TurnFailure(idx, 'turn_timeout');
    } on ProviderTransportFailure catch (e) {
      // The wire died, not the model: a retryable turn failure that rides the
      // existing 3-consecutive-failures ladder.
      final String detail =
          '${e.errorClass}; '
          'provider_request_id=${_lastProviderRequestId ?? 'none'}';
      await _writeFailedTurn(
        idx,
        reason: 'provider_transport',
        providerError: detail,
      );
      _emitTurnEvent(TurnValidation(idx, false, 'provider_transport'));
      _emitTurnEvent(
        TurnUsage(idx, _conversation.estimatedTokens(), _tokenBudget),
      );
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _lastFailureDetail = 'provider_transport: $detail';
      _turnIndex++;
      if (_providerRetryBackoff > Duration.zero) {
        await Future<void>.delayed(_providerRetryBackoff);
      }
      throw TurnFailure(idx, 'provider_transport', e);
    } on InvalidActionExhausted catch (e) {
      await _writeFailedTurn(
        idx,
        reason: 'invalid_action_exhausted',
        rejections: e.rejections,
      );
      _emitTurnEvent(TurnValidation(idx, false, 'invalid_action_exhausted'));
      _emitTurnEvent(
        TurnUsage(idx, _conversation.estimatedTokens(), _tokenBudget),
      );
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _lastFailureDetail = 'invalid_action_exhausted';
      _turnIndex++;
      throw TurnFailure(idx, 'invalid_action_exhausted', e);
    } on SchemaExhausted catch (e) {
      await _writeFailedTurn(
        idx,
        reason: 'schema_exhausted',
        schemaError: e.cause.validationError,
      );
      _emitTurnEvent(TurnValidation(idx, false, 'schema_exhausted'));
      _emitTurnEvent(
        TurnUsage(idx, _conversation.estimatedTokens(), _tokenBudget),
      );
      _emitTurnEvent(TurnComplete(idx));
      _consecutiveFailedTurns++;
      _lastFailureDetail = 'schema_exhausted';
      _turnIndex++;
      throw TurnFailure(idx, 'schema_exhausted', e);
    }
  }

  Future<TurnRecord> _runTurnInner(int idx) async {
    // step 1+2+3: stabilize + deserialize (core + extension fragments).
    final Observation curr = await _host.observe();
    await _accountExtensionStrikes(curr);

    // step 4: diff against the previous turn's observation.
    final ObservationDiff diff = ObservationDiffer.diff(_prev, curr);

    // step 5: build prompt against the CURRENT merged tool list
    // (auto-disabled extensions already excluded). Append a UserTurn
    // carrying any pending failed-action carry-forward, trim stale
    // observations to stay under the token budget, then snapshot.
    final List<ToolDescriptor> mergedTools = _host.mergedTools();
    _conversation.appendUserTurn(curr, diff, toolResult: _pendingToolResult);
    _pendingToolResult = null;
    _conversation.trimIfOverBudget(_tokenBudget);
    final ConversationSnapshot snapshot = _conversation.snapshot();
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
        baseSnapshot: snapshot,
        schema: schema,
        validator: _validator,
        observation: curr,
        mergedTools: mergedTools,
      );
    } finally {
      await thinkingSub?.cancel();
    }

    _lastProviderRequestId =
        v.decision.providerRequestId ?? _lastProviderRequestId;

    // After validate: emit the chosen action + validation outcome.
    _emitTurnEvent(
      TurnActionDecided(idx, v.decision.action.tool, v.decision.action.args),
    );
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

    // step 9: notify extensions.
    await _host.notifyExtensions(
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
      thinking: v.decision.thinking,
      modelMetadata: <String, dynamic>{
        ...v.decision.modelMetadata,
        if (v.decision.rationale != null) 'rationale': v.decision.rationale,
        if (v.decision.waitStrategy != null)
          'wait_strategy': v.decision.waitStrategy,
      },
      providerRequestId: v.decision.providerRequestId,
    );
    await _writer.writeTurn(rec);

    // Append the assistant turn to the conversation; stash any failed-
    // action error for the next turn's user-turn toolResult.
    _conversation.appendAssistantTurn(
      v.decision.thinking ?? '',
      v.decision.action,
    );
    if (exec['ok'] == false) {
      final Object? err = exec['error'];
      _pendingToolResult = <String, dynamic>{
        'error': err is String ? err : err?.toString() ?? 'unknown',
      };
    }
    _prev = curr;

    // step 10 (cont.): usage snapshot + turn boundary marker.
    _emitTurnEvent(
      TurnUsage(idx, _conversation.estimatedTokens(), _tokenBudget),
    );
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
    String? providerError,
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
        if (providerError != null) 'provider_error': providerError,
      },
      executedAction: const <String, dynamic>{},
      diff: const <String, dynamic>{},
      modelMetadata: const <String, dynamic>{},
    );
    await _writer.writeTurn(rec);
  }

  Future<void> _accountExtensionStrikes(Observation curr) async {
    for (final String ns in _host.activeExtensionNamespaces()) {
      // 'core' is exempt: its health is tracked via curr.core (nodes/
      // routeStack/errors), not curr.extensions['core'], which is always null
      // by design (CoreExtension is tools-only — it contributes no perception
      // fragment). Auto-disabling core would collapse the action-schema oneOf
      // and stall the agent.
      if (ns == _kCoreNamespace) continue;
      final ExtensionFragment? frag = curr.extensions[ns];
      // A strike is an actual observe() failure, signalled by the binding as
      // an `error` key in the fragment data map (PRD §17 extension isolation
      // contract). A null/absent fragment means the extension simply had nothing
      // to report this turn (e.g. dio with no in-flight or recent requests) —
      // that is healthy, not a failure. Conflating "no data" with "errored"
      // auto-disabled dio after 3 quiet turns.
      final bool errored = frag != null && frag.data['error'] != null;
      if (!errored) {
        extensionFailures.recordSuccess(ns);
        continue;
      }
      final bool reachedThreshold = extensionFailures.recordFailure(ns);
      if (reachedThreshold) {
        const String reason =
            'auto_disable: 3 consecutive observation failures';
        _host.disableExtension(ns, reason);
        await _writer.writeExtensionDisabled(
          ExtensionDisabledEvent(
            namespace: ns,
            reason: reason,
            turn: _turnIndex,
          ),
        );
      }
    }
  }

  // ===== session loop =====

  /// Run a full session. Returns when one of the PRD §17 termination
  /// conditions fires:
  ///   * 50 turns OR 15 minutes wall-clock → `budget_exhausted`
  ///   * 3 consecutive failed turns → `harness_error agent_stuck`
  ///   * VM connection lost mid-turn → `harness_error connection_lost`
  ///   * malformed observation envelope → `harness_error
  ///     observation_envelope_rejected`
  ///   * any unclassified escaping exception → `harness_error unclassified`
  ///     (the footer names it; the exception still propagates)
  ///   * voluntary `core.done(reason)` → `done`
  ///
  /// On termination the trajectory writer is closed with the final
  /// footer (idempotently). [BindingNotInitializedError] is raised by
  /// `LeonardSession.start()` before [runSession] is
  /// invoked, so it is never observed here.
  Future<SessionTermination> runSession() async {
    _sessionStart = _clock();
    SessionTermination? termination;
    Object? escaped;
    try {
      while (true) {
        if (_turnIndex >= _maxTurns ||
            _clock().difference(_sessionStart!) >= _sessionBudget) {
          termination = SessionTermination(SessionOutcome.budgetExhausted);
          return termination;
        }
        if (_consecutiveFailedTurns >= _kMaxConsecutiveFailedTurns) {
          termination = SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.agentStuck,
            terminationDetail: _lastFailureDetail,
          );
          return termination;
        }
        if (_consecutiveTurnTimeouts >= _kMaxConsecutiveTurnTimeouts) {
          termination = const SessionTermination(
            SessionOutcome.budgetExhausted,
            terminationDetail: 'inference_latency',
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
        } on ObservationEnvelopeError catch (e) {
          termination = SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.observationEnvelopeRejected,
            terminationDetail: 'envelope_keys=${e.keySummary}',
          );
          return termination;
        }
      }
    } catch (error) {
      // Nothing leaves runSession unclassified: record the escapee so the
      // finally clause can NAME it in the footer, then propagate it to the
      // caller exactly as before.
      escaped = error;
      rethrow;
    } finally {
      // Close writer with the appropriate footer (close() is idempotent, so
      // duplicate calls are safe if termination is already set).
      final SessionTermination t =
          termination ??
          SessionTermination(
            SessionOutcome.harnessError,
            harnessError: HarnessError.unclassified,
            terminationDetail: describeThrowable(escaped),
          );
      await _writer.close(
        SessionFooter(
          outcome: t.outcome,
          totalTurns: _turnIndex,
          totalDurationMs: _sessionStart == null
              ? 0
              : _clock().difference(_sessionStart!).inMilliseconds,
          harnessError: t.harnessError?.wireName,
          terminationDetail: t.terminationDetail,
        ),
      );
    }
  }

  // Re-export for tests that want to assert the budget-exhausted wire
  // name without importing the trajectory record directly.
  String get budgetExhaustedWireName => _kBudgetExhaustedWire;
}
