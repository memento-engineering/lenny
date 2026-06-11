import 'package:meta/meta.dart';

import 'perception.dart';
import 'perception_context.dart';
import 'perception_owner.dart';
import 'stateless_perception.dart';

abstract class StatefulPerception extends Perception {
  const StatefulPerception({super.key});

  @factory
  // ignore: undefined_return_type
  PerceptionState createState();

  @override
  StatefulElement createElement() => StatefulElement(this);
}

abstract class PerceptionState<T extends StatefulPerception> {
  T get perception => _element!.perception as T;

  PerceptionContext get context {
    assert(_element != null, 'context accessed outside element lifecycle');
    return _element!;
  }

  StatefulElement? _element;

  @protected
  void initState() {}

  @protected
  void didChangeDependencies() {}

  Perception build(PerceptionContext context);

  @protected
  void dispose() {}

  void perceived(VoidCallback fn) {
    fn();
    _element!.markNeedsHarvest();
  }
}

class StatefulElement extends ComponentElement {
  StatefulElement(StatefulPerception perception) : super(perception) {
    _state = perception.createState();
    _state._element = this;
  }

  late final PerceptionState _state;
  bool _firstBuild = true;
  bool _needsDidChangeDependencies = false;

  // Exposed for testing. Do not use in production code.
  PerceptionState get state => _state;

  @override
  Perception build(PerceptionContext context) => _state.build(context);

  @override
  void dependencyChanged() {
    _needsDidChangeDependencies = true;
    markNeedsHarvest();
  }

  @override
  void performRebuild() {
    if (_firstBuild) {
      _firstBuild = false;
      _state.initState();
      _needsDidChangeDependencies = true;
    }
    if (_needsDidChangeDependencies) {
      _needsDidChangeDependencies = false;
      _state.didChangeDependencies();
    }
    super.performRebuild();
  }

  @override
  void unmount() {
    _state.dispose();
    super.unmount();
  }
}
