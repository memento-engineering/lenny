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
  void mount(PerceptionElement? parent, Object? slot) {
    super.mount(parent, slot);
    // First build is unconditional (Flutter's _firstBuild): a freshly mounted
    // ComponentElement builds its subtree immediately, so mountRoot(p) produces
    // a tree without an external markNeedsHarvest. Subsequent rebuilds still
    // flow through markNeedsHarvest + owner.flushHarvest.
    performRebuild();
  }

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
