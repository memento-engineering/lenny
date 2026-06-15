// GENERATED — do not edit.
// Generated from schema/catalog.json by tool/generate.dart (spike5; emitted by spike3 generateFromCatalog).
//
// Typed factory registry: wire type name -> Perception factory.
// Validates props and children at construction; nothing outside this
// file hardcodes component type names.

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/field.dart';

import '../components.dart';

typedef ComponentFactory =
    Perception Function(
      Map<String, Object?> props,
      List<Perception> children,
      Object? key,
    );

String _stringProp(String type, Map<String, Object?> props, String name) {
  final value = props[name];
  if (value == null) {
    throw StateError(
      'component type "$type": missing required prop "$name"',
    );
  }
  if (value is! String) {
    throw StateError(
      'component type "$type": prop "$name" must be a string, '
      'got ${value.runtimeType} ($value)',
    );
  }
  return value;
}

void _knownPropsOnly(
  String type,
  Map<String, Object?> props,
  Set<String> known,
) {
  for (final key in props.keys) {
    if (!known.contains(key)) {
      throw StateError('component type "$type": unknown prop "$key"');
    }
  }
}

void _noChildren(String type, List<Perception> children) {
  if (children.isNotEmpty) {
    throw StateError(
      'component type "$type" is a leaf and cannot have children '
      '(got ${children.length})',
    );
  }
}

final Map<String, ComponentFactory> componentRegistry = {
  'button': (props, children, key) {
    _noChildren('button', children);
    _knownPropsOnly('button', props, const {'label'});
    return CounterButton(
      label: _stringProp('button', props, 'label'),
      key: key,
    );
  },
  'label': (props, children, key) {
    _noChildren('label', children);
    _knownPropsOnly('label', props, const {'name', 'value'});
    return Field(
      name: _stringProp('label', props, 'name'),
      value: _stringProp('label', props, 'value'),
      key: key,
    );
  },
  'panel': (props, children, key) {
    _knownPropsOnly('panel', props, const {'name'});
    return Node(
      _stringProp('panel', props, 'name'),
      children: children,
      key: key,
    );
  },
};

/// Single entry point used by the wire deserializer. Unknown [type] -> error.
Perception buildComponent(
  String type,
  Map<String, Object?> props,
  List<Perception> children,
  Object? key,
) {
  final factory = componentRegistry[type];
  if (factory == null) {
    throw StateError(
      'unknown component type "$type"; known types: button, label, panel',
    );
  }
  return factory(props, children, key);
}
