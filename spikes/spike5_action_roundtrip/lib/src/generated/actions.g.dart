// GENERATED — do not edit.
// Generated from schema/catalog.json by tool/generate.dart (spike5).
//
// Catalog-derived ACTION AFFORDANCES: which wire component types
// declare which client actions, plus the Perception-class ->
// wire-type mapping the action router uses to hit-test live elements
// against the catalog. Nothing outside this file hardcodes which
// types afford which actions.

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/field.dart';

import '../components.dart';

/// Wire type -> declared action name -> action description.
const Map<String, Map<String, String>> componentActions = {
  'button': {
    'press': 'Increment this button\'s counter by context.amount (integer, optional, default 1).',
    'set': 'Overwrite this button\'s counter with context.value (integer, required). Last write wins.',
  },
  'label': {},
  'panel': {},
};

/// Live Perception instance -> wire type name, via the catalog dart
/// bindings. Null when the perception is not a catalog type.
String? wireTypeOfPerception(Perception perception) {
  if (perception is CounterButton) return 'button';
  if (perception is Field) return 'label';
  if (perception is Node) return 'panel';
  return null;
}
