/// Handle into the Perception tree — the BuildContext analog.
///
/// Pure Dart; zero Flutter imports. Runs in any Dart isolate. See ADR 0001.
abstract class PerceptionContext {
  /// Stable id for this mounted element; assigned at mount time via
  /// [PerceptionOwner.issueId] and never changes during the element's lifetime.
  String get perceptionId;

  /// The key of the underlying [Perception] config, or null if unkeyed.
  Object? get key;

  /// Returns the nearest ancestor value registered via InheritedPerception
  /// of exact type [T], or null. Stub — follow-on bead wires tracking.
  T? dependOnInheritedPerceptionOfExactType<T extends Object>();

  /// Marks this element dirty so the next harvest walk includes it.
  void markNeedsHarvest();
}
