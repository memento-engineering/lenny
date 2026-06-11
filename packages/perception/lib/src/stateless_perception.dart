import 'package:meta/meta.dart';

import 'perception.dart';
import 'perception_context.dart';
import 'perception_element.dart';

abstract class ComponentElement extends PerceptionElement {
  ComponentElement(super.perception);

  PerceptionElement? _child;

  // Exposed for testing.
  PerceptionElement? get child => _child;

  @protected
  Perception build(PerceptionContext context);

  @override
  void performRebuild() {
    _child = updateChild(_child, build(this), 0);
  }

  @override
  void unmount() {
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}

abstract class StatelessPerception extends Perception {
  const StatelessPerception({super.key});

  Perception build(PerceptionContext context);

  @override
  StatelessElement createElement() => StatelessElement(this);
}

class StatelessElement extends ComponentElement {
  StatelessElement(StatelessPerception super.perception);

  @override
  Perception build(PerceptionContext context) =>
      (perception as StatelessPerception).build(context);
}
