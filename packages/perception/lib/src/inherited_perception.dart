import 'perception.dart';
import 'perception_element.dart';

/// Provides an ambient value of type `T` to all descendants in the Perception
/// tree. Emits no output node — the pure-Dart analog of Flutter's InheritedWidget.
///
/// Usage:
///   `InheritedPerception<String>(value: 'hello', child: MyNode())`
///
/// Descendants call:
///   `context.dependOnInheritedPerceptionOfExactType<String>()`
class InheritedPerception<T extends Object> extends Perception {
  const InheritedPerception({
    required this.value,
    required this.child,
    super.key,
  });

  final T value;
  final Perception child;

  /// Returns true when [oldWidget.value] differs from the new [value].
  /// Subclasses may override for custom equality.
  bool updateShouldNotify(InheritedPerception<T> oldWidget) =>
      value != oldWidget.value;

  @override
  InheritedPerceptionElement<T> createElement() =>
      InheritedPerceptionElement<T>(this);
}

/// Mounted element for [InheritedPerception]. Owns the dependent set,
/// reconciles the single child, and invalidates dependents via
/// [PerceptionElement.markNeedsHarvest] when the value changes.
class InheritedPerceptionElement<T extends Object>
    extends InheritedPerceptionBase {
  InheritedPerceptionElement(InheritedPerception<T> super.perception);

  final Set<PerceptionElement> _dependents = {};
  PerceptionElement? _childElement;

  InheritedPerception<T> get _typed => perception as InheritedPerception<T>;

  T get value => _typed.value;

  // --- InheritedPerceptionBase ---

  @override
  U? getValueAs<U extends Object>() => T == U ? value as U : null;

  @override
  void addDependent(PerceptionElement element) {
    _dependents.add(element);
  }

  @override
  void removeDependent(PerceptionElement element) {
    if (_dependents.remove(element)) {
      element.removeDependency(this);
    }
  }

  // Exposed for testing. Do not use in production code.
  Set<PerceptionElement> get dependents => _dependents;

  // Exposed for testing. Do not use in production code.
  PerceptionElement? get childElement => _childElement;

  // --- Lifecycle ---

  @override
  void mount(PerceptionElement? parent, Object? slot) {
    super.mount(parent, slot);
    _childElement = updateChild(null, _typed.child, 0);
  }

  @override
  void update(Perception newPerception) {
    final old = _typed;
    super.update(newPerception);
    _childElement = updateChild(_childElement, _typed.child, 0);
    if (_typed.updateShouldNotify(old)) {
      for (final dep in List.of(_dependents)) {
        dep.markNeedsHarvest();
      }
    }
  }

  @override
  void unmount() {
    for (final dep in List.of(_dependents)) {
      dep.removeDependency(this);
    }
    _dependents.clear();
    _childElement = updateChild(_childElement, null, 0);
    super.unmount();
  }
}
