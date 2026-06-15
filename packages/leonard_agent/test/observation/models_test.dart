import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('Observation.empty', () {
    test('has zero-content prior fields', () {
      final Observation o = Observation.empty();
      expect(o.core.routeStack, isEmpty);
      expect(o.core.nodes, isEmpty);
      expect(o.core.errors, isEmpty);
      expect(o.plugins, isEmpty);
      expect(o.stability.policy, equals(''));
      expect(o.stability.durationMs, equals(0));
    });

    test('two empty instances are equal', () {
      expect(Observation.empty(), equals(Observation.empty()));
    });
  });

  group('Observation.fromJson', () {
    test('rebundles flat wire format into core+plugins+stability', () {
      final Map<String, dynamic> wire = <String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'role': 'button',
            'label': 'OK',
            'rect': <int>[0, 0, 100, 50],
          },
          <String, dynamic>{
            'id': 2,
            'role': 'text',
            'rect': <int>[0, 60, 100, 80],
          },
        ],
        'routes': <String>['/home'],
        'errors': <Map<String, dynamic>>[
          <String, dynamic>{
            'seq': 7,
            'message': 'boom',
            'frames': <String>['#0  main'],
            'wallClockOffsetMs': 123,
          },
        ],
        'stability': <String, dynamic>{
          'policy': 'action_relative',
          'terminated_by': 'idle',
          'duration_ms': 42,
          'framework_busy': <String, dynamic>{'anyBusy': false},
          'extensions_busy': const <Object>[],
        },
        'extensions': <String, dynamic>{
          'router': <String, dynamic>{'path': '/home'},
        },
      };

      final Observation o = Observation.fromJson(wire);
      expect(o.core.nodes.keys, equals(<int>{1, 2}));
      expect(o.core.nodes[1]!.label, equals('OK'));
      expect(o.core.nodes[1]!.rect, equals(<int>[0, 0, 100, 50]));
      expect(o.core.routeStack, equals(<String>['/home']));
      expect(o.core.errors, hasLength(1));
      expect(o.core.errors.first.message, equals('boom'));
      expect(o.plugins.keys, equals(<String>{'router'}));
      expect(o.plugins['router']!.namespace, equals('router'));
      expect(o.plugins['router']!.data, equals(<String, dynamic>{'path': '/home'}));
      expect(o.plugins['router']!.deltaFriendly, isFalse);
      expect(o.stability.policy, equals('action_relative'));
      expect(o.stability.terminatedBy, equals('idle'));
      expect(o.stability.durationMs, equals(42));
    });

    test('absent top-level keys yield empty fields', () {
      final Observation o = Observation.fromJson(const <String, dynamic>{});
      expect(o, equals(Observation.empty()));
    });

    test('plugin fragment honours bare delta_friendly flag', () {
      final Observation o = Observation.fromJson(<String, dynamic>{
        'extensions': <String, dynamic>{
          'router': <String, dynamic>{
            'path': '/x',
            '_delta_friendly': true,
          },
        },
      });
      expect(o.plugins['router']!.deltaFriendly, isTrue);
      // Flag should still be visible inside `data` — we don't strip it,
      // but we treat it as a control marker for diff selection.
      expect(o.plugins['router']!.data['path'], equals('/x'));
    });

    test('plugin fragment supports envelope shape', () {
      final Observation o = Observation.fromJson(<String, dynamic>{
        'extensions': <String, dynamic>{
          'router': <String, dynamic>{
            'namespace': 'router',
            'data': <String, dynamic>{'path': '/x'},
            'delta_friendly': true,
          },
        },
      });
      expect(o.plugins['router']!.deltaFriendly, isTrue);
      expect(o.plugins['router']!.data, equals(<String, dynamic>{'path': '/x'}));
    });

    test('malformed semantics records are skipped, not thrown', () {
      final Observation o = Observation.fromJson(<String, dynamic>{
        'semantics': <Object>[
          <String, dynamic>{'id': 1, 'role': 'button', 'rect': <int>[0, 0, 1, 1]},
          // Missing rect.
          <String, dynamic>{'id': 2, 'role': 'text'},
          // Wrong types.
          'nope',
        ],
      });
      expect(o.core.nodes.keys, equals(<int>{1}));
    });
  });

  group('Observation toJson', () {
    test('round-trips through jsonEncode/jsonDecode for non-trivial fixture',
        () {
      final Map<String, dynamic> wire = <String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 5,
            'role': 'button',
            'label': 'Hi',
            'state': <String>['focused'],
            'actions': <String>['tap'],
            'rect': <int>[1, 2, 3, 4],
          },
        ],
        'routes': <String>['/a', '/b'],
        'errors': <Map<String, dynamic>>[],
        'stability': <String, dynamic>{
          'policy': 'quiet_frame',
          'terminated_by': 'quiet_frame',
          'duration_ms': 7,
          'framework_busy': <String, dynamic>{'anyBusy': false},
          'extensions_busy': const <Object>[],
        },
        'extensions': <String, dynamic>{},
      };
      final Observation a = Observation.fromJson(wire);
      final String enc = jsonEncode(a.toJson());
      // Round-trip through our own toJson shape (not the wire shape).
      final Map<String, dynamic> decoded =
          jsonDecode(enc) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(<String>['core', 'extensions', 'stability']));
      // Determinism: same inputs -> identical bytes.
      expect(jsonEncode(a.toJson()), equals(jsonEncode(a.toJson())));
    });
  });

  group('Observation equality', () {
    test('value equality on identical content', () {
      final Map<String, dynamic> wire = <String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'role': 'button',
            'rect': <int>[0, 0, 1, 1],
          },
        ],
      };
      expect(Observation.fromJson(wire), equals(Observation.fromJson(wire)));
    });

    test('inequality on differing semantics labels', () {
      final Observation a = Observation.fromJson(<String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'role': 'button',
            'label': 'a',
            'rect': <int>[0, 0, 1, 1],
          },
        ],
      });
      final Observation b = Observation.fromJson(<String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'role': 'button',
            'label': 'b',
            'rect': <int>[0, 0, 1, 1],
          },
        ],
      });
      expect(a, isNot(equals(b)));
    });
  });

  group('Observation.screenshot (lenny-wisp-cl4)', () {
    test('Observation.empty() has null screenshot', () {
      expect(Observation.empty().screenshot, isNull);
    });

    test('fromJson populates screenshot from screenshot_png_b64', () {
      final Observation o =
          Observation.fromJson(<String, dynamic>{'screenshot_png_b64': 'AAAA'});
      expect(o.screenshot, equals('AAAA'));
    });

    test('toJson omits screenshot_png_b64 when null', () {
      final Observation o = Observation.empty();
      final Map<String, dynamic> json = o.toJson();
      expect(json.containsKey('screenshot_png_b64'), isFalse);
    });

    test('toJson emits screenshot_png_b64 when non-null', () {
      final Observation o = Observation.fromJson(
          <String, dynamic>{'screenshot_png_b64': 'XYZ='});
      final Map<String, dynamic> json = o.toJson();
      expect(json['screenshot_png_b64'], equals('XYZ='));
    });

    test('two Observations with different screenshots are not equal', () {
      final Observation a = Observation.fromJson(
          <String, dynamic>{'screenshot_png_b64': 'A'});
      final Observation b = Observation.fromJson(
          <String, dynamic>{'screenshot_png_b64': 'B'});
      expect(a, isNot(equals(b)));
    });

    test('screenshot round-trips through toJson + fromJson', () {
      final Observation original = Observation.fromJson(<String, dynamic>{
        'semantics': <Map<String, dynamic>>[],
        'screenshot_png_b64': 'round-trip',
      });
      final Observation restored = Observation.fromJson(original.toJson());
      expect(restored.screenshot, equals('round-trip'));
      expect(restored, equals(original));
    });
  });
}
