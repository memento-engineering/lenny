import 'package:perception/perception.dart';

/// Spike-local leaf vocabulary. There is intentionally NO Field in
/// package:perception — the spike defines its own leaf type to prove that
/// catalog-driven codegen can bind to types outside the framework package.
class Field extends Perception {
  const Field({required this.name, required this.value, super.key});

  final String name;
  final String value;

  @override
  FieldElement createElement() => FieldElement(this);
}

/// Trivial leaf element: no children, no build phase.
class FieldElement extends PerceptionElement {
  FieldElement(Field super.perception);
}
