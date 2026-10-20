/// Per-call usage accounting for a session (lenny#178).
///
/// The loop driver wraps its provider in a [MeteredModelProvider], which
/// records every `decide` call — accepted, schema-rejected, or failed on the
/// wire — into a [RunUsageLedger] under the turn it started in. Retries are
/// separate calls, so a turn that spent a schema retry and two validator
/// retries is four calls, all billed. A call the turn budget gives up on is
/// recorded too ([ModelCallOutcome.abandoned]): nothing cancels its request,
/// so it still runs and, on a hosted provider, still bills. The ledger then
/// renders a turn's calls into its trajectory record and the whole run into
/// the footer.
library;

import 'package:meta/meta.dart';

import '../provider/action_schema.dart';
import '../provider/model_provider.dart';
import '../provider/model_usage.dart';
import '../provider/types.dart';
import 'provider_transport.dart';

/// How one model call ended.
enum ModelCallOutcome {
  /// The provider returned a decision (the validator may still reject it).
  ok('ok'),

  /// The provider threw [SchemaRejection].
  schemaRejection('schema_rejection'),

  /// The wire failed (see [isProviderTransportError]).
  transportError('transport_error'),

  /// Any other exception.
  error('error'),

  /// The turn budget expired while the call was in flight. Its usage is
  /// attached if the call later completes before the run ends.
  abandoned('abandoned');

  const ModelCallOutcome(this.wireName);

  /// The trajectory spelling.
  final String wireName;
}

/// One recorded model call.
@immutable
class ModelCallRecord {
  /// Creates a record of a call made during [turn].
  const ModelCallRecord({
    required this.turn,
    required this.outcome,
    required this.latencyMs,
    this.usage,
  });

  /// The turn index the call started in.
  final int turn;

  /// How the call ended.
  final ModelCallOutcome outcome;

  /// Wall-clock milliseconds the call took.
  final int latencyMs;

  /// What the provider reported, or null when it reported nothing.
  final ModelCallUsage? usage;

  /// Output tokens per second over the generation phase (after the first
  /// token), or null when the call lacks the figures.
  double? get outputTokensPerSecond {
    final int? out = usage?.outputTokens;
    final int? ttft = usage?.timeToFirstTokenMs;
    if (out == null || ttft == null || latencyMs <= ttft) return null;
    return out * 1000 / (latencyMs - ttft);
  }

  /// Encodes this call for a turn record.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'outcome': outcome.wireName,
    'latency_ms': latencyMs,
    if (usage?.inputTokens != null) 'input_tokens': usage!.inputTokens,
    if (usage?.outputTokens != null) 'output_tokens': usage!.outputTokens,
    if (usage?.timeToFirstTokenMs != null)
      'time_to_first_token_ms': usage!.timeToFirstTokenMs,
    if (outputTokensPerSecond != null)
      'output_tokens_per_second': _round(outputTokensPerSecond!),
  };
}

/// Accumulates [ModelCallRecord]s for one session.
class RunUsageLedger {
  final List<ModelCallRecord> _calls = <ModelCallRecord>[];

  /// Every call recorded so far, in completion order.
  List<ModelCallRecord> get calls => List.unmodifiable(_calls);

  /// Records [call], returning its index for [replace].
  int record(ModelCallRecord call) {
    _calls.add(call);
    return _calls.length - 1;
  }

  /// Replaces the call recorded at [index] (an abandoned call's late usage).
  void replace(int index, ModelCallRecord call) => _calls[index] = call;

  /// The `usage` entry for turn [turn]'s `model_metadata`, or null when the
  /// turn made no model call (e.g. it timed out while observing).
  Map<String, dynamic>? turnUsage(int turn) {
    final List<ModelCallRecord> turnCalls = <ModelCallRecord>[
      for (final ModelCallRecord c in _calls)
        if (c.turn == turn) c,
    ];
    if (turnCalls.isEmpty) return null;
    return <String, dynamic>{
      ..._totals(turnCalls),
      'calls': <Map<String, dynamic>>[
        for (final ModelCallRecord c in turnCalls) c.toJson(),
      ],
    };
  }

  /// The footer's `usage` entry for the whole run, costed by [pricing].
  ///
  /// `estimated_cost_usd` is always present: a number when the run's model
  /// has a price and reported tokens, otherwise null — unset, never zero.
  Map<String, dynamic> runUsage(ModelPricing pricing) {
    final ModelCallUsage? identity = _lastIdentity();
    final Map<String, dynamic> totals = _totals(_calls);
    final ModelPrice? price = pricing.priceFor(
      provider: identity?.provider,
      model: identity?.model,
    );
    final int? input = totals['input_tokens'] as int?;
    final int? output = totals['output_tokens'] as int?;
    final double? cost = price == null || (input == null && output == null)
        ? null
        : price.cost(inputTokens: input ?? 0, outputTokens: output ?? 0);
    return <String, dynamic>{
      if (identity?.provider != null) 'provider': identity!.provider,
      if (identity?.model != null) 'model': identity!.model,
      ...totals,
      'estimated_cost_usd': cost == null ? null : _round(cost, places: 6),
      if (price != null)
        'price': <String, dynamic>{
          'input_per_mtok': price.inputPerMTok,
          'output_per_mtok': price.outputPerMTok,
          'source': pricing.source,
        },
    };
  }

  ModelCallUsage? _lastIdentity() {
    for (final ModelCallRecord c in _calls.reversed) {
      final ModelCallUsage? u = c.usage;
      if (u != null && (u.provider != null || u.model != null)) return u;
    }
    return null;
  }

  static Map<String, dynamic> _totals(List<ModelCallRecord> calls) {
    int? input;
    int? output;
    int latency = 0;
    int withoutUsage = 0;
    int ttftSum = 0;
    int ttftCount = 0;
    int generatedTokens = 0;
    int generationMs = 0;
    for (final ModelCallRecord c in calls) {
      latency += c.latencyMs;
      final ModelCallUsage? u = c.usage;
      if (u?.inputTokens == null && u?.outputTokens == null) withoutUsage++;
      if (u?.inputTokens != null) input = (input ?? 0) + u!.inputTokens!;
      if (u?.outputTokens != null) output = (output ?? 0) + u!.outputTokens!;
      final int? ttft = u?.timeToFirstTokenMs;
      if (ttft != null) {
        ttftSum += ttft;
        ttftCount++;
        if (u?.outputTokens != null && c.latencyMs > ttft) {
          generatedTokens += u!.outputTokens!;
          generationMs += c.latencyMs - ttft;
        }
      }
    }
    return <String, dynamic>{
      'model_calls': calls.length,
      if (withoutUsage > 0) 'calls_without_usage': withoutUsage,
      if (input != null) 'input_tokens': input,
      if (output != null) 'output_tokens': output,
      'model_latency_ms': latency,
      if (ttftCount > 0)
        'mean_time_to_first_token_ms': (ttftSum / ttftCount).round(),
      if (generationMs > 0)
        'output_tokens_per_second': _round(
          generatedTokens * 1000 / generationMs,
        ),
    };
  }
}

/// A [ModelProvider] that records every [decide] call into [ledger] under the
/// turn [currentTurn] reports when the call starts, then passes the result or
/// exception through untouched.
///
/// A call still in flight when its turn is given up on is recorded by
/// [abandonInFlight]; if it completes later, its usage replaces that record's
/// rather than adding a second call.
class MeteredModelProvider implements ModelProvider {
  /// Wraps [inner].
  MeteredModelProvider({
    required ModelProvider inner,
    required this.ledger,
    required int Function() currentTurn,
    required DateTime Function() clock,
  }) : _inner = inner,
       _currentTurn = currentTurn,
       _clock = clock;

  final ModelProvider _inner;
  final int Function() _currentTurn;
  final DateTime Function() _clock;
  final Set<_InFlightCall> _inFlight = <_InFlightCall>{};

  /// Where calls are recorded.
  final RunUsageLedger ledger;

  @override
  ModelCapabilities get capabilities => _inner.capabilities;

  @override
  Stream<ThinkingDelta> thinking() => _inner.thinking();

  /// Records every call still in flight as [ModelCallOutcome.abandoned], with
  /// the latency so far and no usage. Called when a turn's budget expires,
  /// before its failed-turn record is written.
  void abandonInFlight() {
    for (final _InFlightCall call in _inFlight) {
      call.abandonedAt = ledger.record(
        ModelCallRecord(
          turn: call.turn,
          outcome: ModelCallOutcome.abandoned,
          latencyMs: _clock().difference(call.start).inMilliseconds,
        ),
      );
    }
    _inFlight.clear();
  }

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final _InFlightCall call = _InFlightCall(_currentTurn(), _clock());
    _inFlight.add(call);
    void record(ModelCallOutcome outcome, ModelCallUsage? usage) {
      _inFlight.remove(call);
      final int latencyMs = _clock().difference(call.start).inMilliseconds;
      if (call.abandonedAt case final int index) {
        // Late: the turn already gave up. Keep the abandoned outcome, but the
        // provider did the work, so its usage and real latency count.
        ledger.replace(
          index,
          ModelCallRecord(
            turn: call.turn,
            outcome: ModelCallOutcome.abandoned,
            latencyMs: latencyMs,
            usage: usage,
          ),
        );
        return;
      }
      ledger.record(
        ModelCallRecord(
          turn: call.turn,
          outcome: outcome,
          latencyMs: latencyMs,
          usage: usage,
        ),
      );
    }

    try {
      final ModelDecision decision = await _inner.decide(snapshot, schema);
      record(ModelCallOutcome.ok, decision.usage);
      return decision;
    } on SchemaRejection catch (rejection) {
      record(ModelCallOutcome.schemaRejection, rejection.usage);
      rethrow;
    } catch (error) {
      record(
        isProviderTransportError(error)
            ? ModelCallOutcome.transportError
            : ModelCallOutcome.error,
        null,
      );
      rethrow;
    }
  }
}

class _InFlightCall {
  _InFlightCall(this.turn, this.start);

  final int turn;
  final DateTime start;

  /// The ledger index of this call's abandoned record, once abandoned.
  int? abandonedAt;
}

double _round(double value, {int places = 2}) {
  final String fixed = value.toStringAsFixed(places);
  return double.parse(fixed);
}
