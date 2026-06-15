import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('CoreDiff.toJson', () {
    test('emits all five fields with stable shapes', () {
      const SemanticsNode n = SemanticsNode(
        id: 1,
        role: 'button',
        label: 'A',
        state: <String>[],
        actions: <String>[],
        rect: <int>[0, 0, 1, 1],
      );
      final CoreDiff d = CoreDiff(
        routeChanges: <RouteChange>[
          const RouteChange(
            previous: <String>['/a'],
            current: <String>['/a', '/b'],
          ),
        ],
        nodesAdded: <SemanticsNode>[n],
        nodesRemoved: <int>[7, 9],
        nodesChanged: <NodeChange>[],
        errorsAdded: <RuntimeError>[],
      );
      final Map<String, dynamic> j = d.toJson();
      expect(
        j.keys,
        equals(<String>[
          'routeChanges',
          'nodesAdded',
          'nodesRemoved',
          'nodesChanged',
          'errorsAdded',
        ]),
      );
      expect(j['nodesRemoved'], equals(<int>[7, 9]));
      expect(
        (j['routeChanges'] as List).first['current'],
        equals(<String>['/a', '/b']),
      );
    });
  });

  group('ExtensionDiff variants', () {
    test('ExtensionDiffStructured emits sorted added/removed/changed keys', () {
      const ExtensionDiffStructured d = ExtensionDiffStructured(
        added: <String, dynamic>{'b': 2, 'a': 1},
        removed: <String, dynamic>{'z': 9, 'y': 8},
        changed: <String, ChangedValue>{
          'q': ChangedValue(prev: 1, curr: 2),
          'p': ChangedValue(prev: 'x', curr: 'y'),
        },
      );
      final Map<String, dynamic> j = d.toJson();
      expect(j['kind'], equals('structured'));
      expect((j['added'] as Map).keys.toList(), equals(<String>['a', 'b']));
      expect((j['removed'] as Map).keys.toList(), equals(<String>['y', 'z']));
      expect((j['changed'] as Map).keys.toList(), equals(<String>['p', 'q']));
      expect(
        ((j['changed'] as Map)['q'] as Map),
        equals(<String, dynamic>{'prev': 1, 'curr': 2}),
      );
    });

    test('ExtensionDiffOpaque emits previous+current', () {
      const ExtensionDiffOpaque d = ExtensionDiffOpaque(
        previous: <String, dynamic>{'a': 1},
        current: <String, dynamic>{'a': 2},
      );
      expect(
        d.toJson(),
        equals(<String, dynamic>{
          'kind': 'opaque',
          'previous': <String, dynamic>{'a': 1},
          'current': <String, dynamic>{'a': 2},
        }),
      );
    });

    test('ExtensionDiffAdded carries kind=added + current', () {
      const ExtensionDiffAdded d = ExtensionDiffAdded(
        current: <String, dynamic>{'x': 1},
      );
      expect(
        d.toJson(),
        equals(<String, dynamic>{
          'kind': 'added',
          'current': <String, dynamic>{'x': 1},
        }),
      );
    });

    test('ExtensionDiffRemoved carries kind=removed + previous', () {
      const ExtensionDiffRemoved d = ExtensionDiffRemoved(
        previous: <String, dynamic>{'x': 1},
      );
      expect(
        d.toJson(),
        equals(<String, dynamic>{
          'kind': 'removed',
          'previous': <String, dynamic>{'x': 1},
        }),
      );
    });
  });

  group('ObservationDiff.toJson', () {
    test(
      'extension keys are alphabetized in output regardless of insertion order',
      () {
        final ObservationDiff d = ObservationDiff(
          core: const CoreDiff(
            routeChanges: <RouteChange>[],
            nodesAdded: <SemanticsNode>[],
            nodesRemoved: <int>[],
            nodesChanged: <NodeChange>[],
            errorsAdded: <RuntimeError>[],
          ),
          extensions: <String, ExtensionDiff>{
            'zeta': const ExtensionDiffAdded(current: <String, dynamic>{}),
            'alpha': const ExtensionDiffAdded(current: <String, dynamic>{}),
            'mu': const ExtensionDiffAdded(current: <String, dynamic>{}),
          },
        );
        final Map<String, dynamic> j = d.toJson();
        expect(
          (j['extensions'] as Map).keys.toList(),
          equals(<String>['alpha', 'mu', 'zeta']),
        );
        // Determinism: jsonEncode is byte-stable for repeated calls.
        expect(jsonEncode(d.toJson()), equals(jsonEncode(d.toJson())));
      },
    );
  });

  group('RouteChange/NodeChange/ChangedValue', () {
    test('toJson shapes are stable', () {
      const RouteChange r = RouteChange(
        previous: <String>['/a'],
        current: <String>['/b'],
      );
      expect(
        r.toJson(),
        equals(<String, dynamic>{
          'previous': <String>['/a'],
          'current': <String>['/b'],
        }),
      );

      const SemanticsNode a = SemanticsNode(
        id: 1,
        role: 'button',
        label: 'a',
        state: <String>[],
        actions: <String>[],
        rect: <int>[0, 0, 1, 1],
      );
      const SemanticsNode b = SemanticsNode(
        id: 1,
        role: 'button',
        label: 'b',
        state: <String>[],
        actions: <String>[],
        rect: <int>[0, 0, 1, 1],
      );
      final NodeChange nc = NodeChange(prev: a, curr: b);
      expect(nc.toJson()['prev'], equals(a.toJson()));
      expect(nc.toJson()['curr'], equals(b.toJson()));

      const ChangedValue cv = ChangedValue(prev: 1, curr: 2);
      expect(cv.toJson(), equals(<String, dynamic>{'prev': 1, 'curr': 2}));
    });
  });
}
