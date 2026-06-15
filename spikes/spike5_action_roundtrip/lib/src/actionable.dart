/// Handler-level contract between the action router and live component state.
///
/// The router performs the catalog hit-test (does this component exist, is it
/// mounted, does its catalog type declare the action); the state performs the
/// payload-level validation and — only when valid — the ENFORCEMENT, mutating
/// inside [PerceptionState.perceived] so exactly its own subtree is
/// invalidated.
library;

/// Outcome of dispatching a hit-tested action intent to a component's state.
sealed class ActionOutcome {}

/// The intent was enforced. [change] describes what changed,
/// e.g. {'count': {'from': 0, 'to': 1}}.
class HandledChange extends ActionOutcome {
  HandledChange(this.change);

  final Map<String, Object?> change;
}

/// The intent's payload (A2UI `context`) failed validation. NO mutation was
/// performed — the router surfaces this as Rejection(badPayload).
class PayloadError extends ActionOutcome {
  PayloadError(this.detail);

  final String detail;
}

/// Implemented by PerceptionStates that can receive routed action intents.
abstract interface class ActionableState {
  /// [name] has already been hit-tested against the catalog affordances for
  /// this component's type; [context] is the action message's context/payload.
  ActionOutcome handleAction(String name, Map<String, Object?> context);
}
