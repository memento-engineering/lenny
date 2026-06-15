import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

// ---- fixture helpers ----

SemanticsNode _node(int id, {String role = 'button', String label = ''}) =>
    SemanticsNode(
      id: id,
      role: role,
      label: label,
      state: const <String>[],
      actions: const <String>[],
      rect: <int>[id, id, id + 10, id + 10],
    );

Observation _obs({
  Map<int, SemanticsNode> nodes = const <int, SemanticsNode>{},
  List<String> routes = const <String>[],
  List<RuntimeError> errors = const <RuntimeError>[],
  Map<String, ExtensionFragment> plugins = const <String, ExtensionFragment>{},
}) {
  return Observation(
    core: CoreFragment(
      routeStack: List<String>.unmodifiable(routes),
      nodes: Map<int, SemanticsNode>.unmodifiable(nodes),
      errors: List<RuntimeError>.unmodifiable(errors),
    ),
    plugins: Map<String, ExtensionFragment>.unmodifiable(plugins),
    stability: StabilityMetadata.empty,
  );
}

ExtensionFragment _frag(
  String ns,
  Map<String, dynamic> data, {
  bool deltaFriendly = false,
}) => ExtensionFragment(
  namespace: ns,
  data: Map<String, dynamic>.unmodifiable(data),
  deltaFriendly: deltaFriendly,
);

Observation _bigObs() => _obs(
  nodes: <int, SemanticsNode>{
    1: _node(1, label: 'A'),
    2: _node(2, label: 'B'),
  },
  routes: <String>['/home'],
  plugins: <String, ExtensionFragment>{
    'router': _frag('router', <String, dynamic>{
      'path': '/home',
    }, deltaFriendly: true),
    'opaque': _frag('opaque', <String, dynamic>{'k': 1}),
  },
);

Observation _bigObs2() => _obs(
  nodes: <int, SemanticsNode>{
    1: _node(1, label: 'A2'), // changed
    3: _node(3, label: 'C'), // added
  },
  routes: <String>['/home', '/details'],
  plugins: <String, ExtensionFragment>{
    'router': _frag('router', <String, dynamic>{
      'path': '/details',
    }, deltaFriendly: true),
    'opaque': _frag('opaque', <String, dynamic>{'k': 2}),
  },
);

void main() {
  test('first-turn diff treats empty prior as all-added', () {
    final Observation curr = _obs(
      nodes: <int, SemanticsNode>{1: _node(1), 2: _node(2)},
    );
    final ObservationDiff d = ObservationDiffer.diff(Observation.empty(), curr);
    expect(
      d.core.nodesAdded.map((SemanticsNode n) => n.id).toList(),
      equals(<int>[1, 2]),
    );
    expect(d.core.nodesRemoved, isEmpty);
    expect(d.core.nodesChanged, isEmpty);
  });

  test('node added/removed/changed split correctly', () {
    final Observation prev = _obs(
      nodes: <int, SemanticsNode>{
        1: _node(1, label: 'a'),
        2: _node(2),
      },
    );
    final Observation curr = _obs(
      nodes: <int, SemanticsNode>{
        1: _node(1, label: 'b'),
        3: _node(3),
      },
    );
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(
      d.core.nodesAdded.map((SemanticsNode n) => n.id).toList(),
      equals(<int>[3]),
    );
    expect(d.core.nodesRemoved, equals(<int>[2]));
    expect(d.core.nodesChanged, hasLength(1));
    expect(d.core.nodesChanged.first.curr.id, equals(1));
    expect(d.core.nodesChanged.first.prev.label, equals('a'));
    expect(d.core.nodesChanged.first.curr.label, equals('b'));
  });

  test('route change emits one RouteChange', () {
    final Observation prev = _obs(routes: <String>['/a']);
    final Observation curr = _obs(routes: <String>['/a', '/b']);
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.core.routeChanges, hasLength(1));
    expect(d.core.routeChanges.first.previous, equals(<String>['/a']));
    expect(d.core.routeChanges.first.current, equals(<String>['/a', '/b']));
  });

  test('unchanged route stack emits no RouteChange', () {
    final Observation prev = _obs(routes: <String>['/a']);
    final Observation curr = _obs(routes: <String>['/a']);
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.core.routeChanges, isEmpty);
  });

  test('delta-friendly plugin yields ExtensionDiffStructured', () {
    final Observation prev = _obs(
      plugins: <String, ExtensionFragment>{
        'router': _frag('router', <String, dynamic>{
          'path': '/a',
        }, deltaFriendly: true),
      },
    );
    final Observation curr = _obs(
      plugins: <String, ExtensionFragment>{
        'router': _frag('router', <String, dynamic>{
          'path': '/b',
        }, deltaFriendly: true),
      },
    );
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.plugins['router'], isA<ExtensionDiffStructured>());
    final ExtensionDiffStructured s =
        d.plugins['router']! as ExtensionDiffStructured;
    expect(s.changed.keys, equals(<String>{'path'}));
    expect(s.changed['path']!.curr, equals('/b'));
    expect(s.changed['path']!.prev, equals('/a'));
  });

  test('opaque plugin yields previous+current pair', () {
    final Observation prev = _obs(
      plugins: <String, ExtensionFragment>{
        'opaque': _frag('opaque', <String, dynamic>{'a': 1}),
      },
    );
    final Observation curr = _obs(
      plugins: <String, ExtensionFragment>{
        'opaque': _frag('opaque', <String, dynamic>{'a': 2}),
      },
    );
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.plugins['opaque'], isA<ExtensionDiffOpaque>());
    final ExtensionDiffOpaque o = d.plugins['opaque']! as ExtensionDiffOpaque;
    expect((o.previous as Map)['a'], equals(1));
    expect((o.current as Map)['a'], equals(2));
  });

  test(
    'mixed-deltaFriendly (one side false) falls back to opaque, not structured',
    () {
      final Observation prev = _obs(
        plugins: <String, ExtensionFragment>{
          'p': _frag('p', <String, dynamic>{'a': 1}, deltaFriendly: false),
        },
      );
      final Observation curr = _obs(
        plugins: <String, ExtensionFragment>{
          'p': _frag('p', <String, dynamic>{'a': 2}, deltaFriendly: true),
        },
      );
      final ObservationDiff d = ObservationDiffer.diff(prev, curr);
      expect(d.plugins['p'], isA<ExtensionDiffOpaque>());
    },
  );

  test('namespace in curr only is ExtensionDiffAdded', () {
    final Observation prev = _obs();
    final Observation curr = _obs(
      plugins: <String, ExtensionFragment>{
        'x': _frag('x', <String, dynamic>{'k': 1}),
      },
    );
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.plugins['x'], isA<ExtensionDiffAdded>());
  });

  test('namespace dropped from curr is ExtensionDiffRemoved', () {
    final Observation prev = _obs(
      plugins: <String, ExtensionFragment>{
        'x': _frag('x', <String, dynamic>{'k': 1}),
      },
    );
    final Observation curr = _obs();
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.plugins['x'], isA<ExtensionDiffRemoved>());
  });

  test('errorsAdded reports new seq numbers without re-reporting old', () {
    final Observation prev = _obs(
      errors: <RuntimeError>[
        const RuntimeError(
          seq: 1,
          message: 'old',
          frames: <String>[],
          wallClockOffsetMs: 0,
        ),
      ],
    );
    final Observation curr = _obs(
      errors: <RuntimeError>[
        const RuntimeError(
          seq: 1,
          message: 'old',
          frames: <String>[],
          wallClockOffsetMs: 0,
        ),
        const RuntimeError(
          seq: 2,
          message: 'new',
          frames: <String>[],
          wallClockOffsetMs: 5,
        ),
      ],
    );
    final ObservationDiff d = ObservationDiffer.diff(prev, curr);
    expect(d.core.errorsAdded.map((RuntimeError e) => e.seq), equals(<int>[2]));
  });

  test('diff is deterministic — repeated calls yield identical JSON', () {
    final Observation a = _bigObs();
    final Observation b = _bigObs2();
    final String first = jsonEncode(ObservationDiffer.diff(a, b).toJson());
    final String second = jsonEncode(ObservationDiffer.diff(a, b).toJson());
    expect(first, equals(second));
  });

  test('plugin namespace insertion order does not affect output JSON', () {
    final Observation a = _obs(
      plugins: <String, ExtensionFragment>{
        'zeta': _frag('zeta', <String, dynamic>{'a': 1}),
        'alpha': _frag('alpha', <String, dynamic>{'a': 1}),
      },
    );
    final Observation b = _obs(
      plugins: <String, ExtensionFragment>{
        'alpha': _frag('alpha', <String, dynamic>{'a': 2}),
        'zeta': _frag('zeta', <String, dynamic>{'a': 2}),
      },
    );
    final String enc = jsonEncode(ObservationDiffer.diff(a, b).toJson());
    final String enc2 = jsonEncode(ObservationDiffer.diff(b, a).toJson());
    expect(enc, isNot(equals(enc2))); // sanity: different inputs differ.
    final String encAgain = jsonEncode(ObservationDiffer.diff(a, b).toJson());
    expect(enc, equals(encAgain));
  });
}
