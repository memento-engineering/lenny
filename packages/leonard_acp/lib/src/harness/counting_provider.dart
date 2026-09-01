/// [ModelProvider] decorator that counts turns and schema rejections.
///
/// The number this spike exists to produce is the [SchemaRejection] RATE over
/// a real session. `LoopDriver` swallows the first rejection per turn (it owns
/// the single retry), so counting has to happen at the provider boundary —
/// not by inspecting the trajectory after the fact.
library;

import 'package:leonard_agent/leonard_agent.dart';

/// Wraps a provider and tallies decide() outcomes.
class CountingModelProvider implements ModelProvider {
  CountingModelProvider(this._inner);

  final ModelProvider _inner;

  /// Total decide() calls, retries included.
  int get attempts => _attempts;
  int _attempts = 0;

  /// decide() calls that threw [SchemaRejection].
  int get rejections => _rejections;
  int _rejections = 0;

  /// Wall-clock spent inside decide().
  Duration get elapsed => _elapsed;
  Duration _elapsed = Duration.zero;

  /// Every rejection reason, in order — the qualitative half of the result.
  final List<String> rejectionReasons = <String>[];

  /// Rejections as a fraction of attempts. Zero when nothing ran.
  double get rejectionRate => _attempts == 0 ? 0 : _rejections / _attempts;

  @override
  ModelCapabilities get capabilities => _inner.capabilities;

  @override
  Stream<ThinkingDelta> thinking() => _inner.thinking();

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    _attempts++;
    final Stopwatch sw = Stopwatch()..start();
    try {
      return await _inner.decide(snapshot, schema);
    } on SchemaRejection catch (e) {
      _rejections++;
      rejectionReasons.add(e.validationError);
      rethrow;
    } finally {
      _elapsed += sw.elapsed;
    }
  }
}
