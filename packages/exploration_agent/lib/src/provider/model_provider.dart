import 'action_schema.dart';
import 'types.dart';

/// Provider contract for model backends used by the exploration agent.
///
/// Concrete implementations land in .15 (swift-infer / local MLX) and
/// .16 / .36 / .37 (frontier providers).
///
/// Retry contract: on a schema violation, providers throw
/// [SchemaRejection]. The loop driver (.18) retries the turn once with
/// the validation error injected back into the prompt; a second failure
/// counts as a failed turn (PRD §17). Provider implementations MUST NOT
/// retry internally — the driver owns retry policy.
abstract class ModelProvider {
  /// Capabilities advertised by this provider — used by the host to
  /// default behaviours such as screenshot capture (gated on
  /// [ModelCapabilities.vision]).
  ModelCapabilities get capabilities;

  /// Live thinking/reasoning stream for the DevTools thinking panel.
  Stream<ThinkingDelta> thinking();

  /// Run one decision turn against the chat-shape [snapshot],
  /// constrained by [schema]. Renders the snapshot into the provider's
  /// native multi-turn message shape, returns a [ModelDecision] whose
  /// `thinking` field carries any reasoning text the model produced
  /// (for carry-forward into the next assistant turn).
  ///
  /// Throws [SchemaRejection] when the model output cannot be parsed
  /// against [schema]. The caller (.18) retries once on rejection.
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  );
}
