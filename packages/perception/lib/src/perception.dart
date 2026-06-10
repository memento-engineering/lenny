import 'perception_element.dart';

/// Immutable configuration node — the Widget analog.
///
/// Pure Dart; zero Flutter imports. See ADR 0001.
abstract class Perception {
  const Perception({this.key});

  final Object? key;

  PerceptionElement createElement();

  static bool canUpdate(Perception a, Perception b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}
