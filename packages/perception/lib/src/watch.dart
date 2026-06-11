import 'dart:async';

import 'perception.dart';
import 'perception_context.dart';
import 'stateful_perception.dart';

class Watch<T> extends StatefulPerception {
  const Watch(
    this.source,
    this.builder, {
    required this.initialValue,
    super.key,
  });

  final Stream<T> source;
  final Perception Function(T value) builder;
  final T initialValue;

  @override
  WatchState<T> createState() => WatchState<T>();
}

class WatchState<T> extends PerceptionState<Watch<T>> {
  late T _value;
  StreamSubscription<T>? _subscription;

  @override
  void initState() {
    _value = perception.initialValue;
    _subscription = perception.source.listen((event) {
      perceived(() => _value = event);
    });
  }

  @override
  Perception build(PerceptionContext context) => perception.builder(_value);

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
