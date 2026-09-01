import 'dart:convert';

import 'package:leonard_flutter/src/observation/budgeted_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeCoreWithBudget', () {
    test('defaults the core budget to 32768 bytes', () {
      expect(kCoreBudgetBytes, 32768);
    });

    test('under-budget core round-trips verbatim', () {
      final Map<String, Object?> fragment = <String, Object?>{
        'semantics': <Object?>[],
        'routes': <String>['/panel'],
        'errors': <Object?>[],
        'stability': <String, Object?>{'policy': 'action-relative'},
      };

      final BudgetedJson out = encodeCoreWithBudget(fragment, 4096);

      expect(out.truncated, isFalse);
      expect(jsonDecode(out.json), fragment);
      expect(out.bytes, utf8.encode(out.json).length);
    });

    test('oversized core drops the semantics tail and preserves metadata', () {
      final Map<String, Object?> fragment = <String, Object?>{
        'semantics': <Object?>[
          <String, Object?>{'id': 1, 'label': 'root'},
          <String, Object?>{'id': 2, 'label': 'child-${'x' * 80}'},
          <String, Object?>{'id': 3, 'label': 'deep-child-${'y' * 80}'},
        ],
        'routes': <String>['/panel'],
        'errors': <Object?>[],
        'stability': <String, Object?>{'policy': 'action-relative'},
      };
      final int originalBytes = utf8.encode(jsonEncode(fragment)).length;
      final Map<String, Object?> oneNode = <String, Object?>{
        ...fragment,
        'semantics': <Object?>[
          <String, Object?>{'id': 1, 'label': 'root'},
        ],
        '_truncated': true,
        'originalBytes': originalBytes,
        'budgetBytes': 0,
        'droppedNodes': 2,
      };
      int budget = utf8.encode(jsonEncode(oneNode)).length;
      oneNode['budgetBytes'] = budget;
      budget = utf8.encode(jsonEncode(oneNode)).length;

      final BudgetedJson out = encodeCoreWithBudget(fragment, budget);
      final Map<String, Object?> decoded =
          jsonDecode(out.json) as Map<String, Object?>;

      expect(out.truncated, isTrue);
      expect(out.bytes, lessThanOrEqualTo(budget));
      expect(decoded['semantics'], <Object?>[
        <String, Object?>{'id': 1, 'label': 'root'},
      ]);
      expect(decoded['routes'], <String>['/panel']);
      expect(decoded['errors'], <Object?>[]);
      expect(decoded['stability'], isNotNull);
      expect(decoded['_truncated'], isTrue);
      expect(decoded['originalBytes'], originalBytes);
      expect(decoded['budgetBytes'], budget);
      expect(decoded['droppedNodes'], 2);
    });

    test('tiny budget retains mandatory metadata after dropping all nodes', () {
      final Map<String, Object?> fragment = <String, Object?>{
        'semantics': <Object?>[
          <String, Object?>{'id': 1},
          <String, Object?>{'id': 2},
        ],
        'routes': <String>['/panel'],
        'errors': <Object?>[],
        'stability': <String, Object?>{'policy': 'action-relative'},
      };

      final BudgetedJson out = encodeCoreWithBudget(fragment, 1);
      final Map<String, Object?> decoded =
          jsonDecode(out.json) as Map<String, Object?>;

      expect(out.truncated, isTrue);
      expect(out.bytes, greaterThan(1));
      expect(decoded['semantics'], isEmpty);
      expect(decoded['routes'], <String>['/panel']);
      expect(decoded['errors'], <Object?>[]);
      expect(decoded['stability'], isNotNull);
      expect(decoded['droppedNodes'], 2);
    });
  });

  group('encodeWithBudget passthrough', () {
    test('fragment under budget round-trips verbatim', () {
      final BudgetedJson out = encodeWithBudget(<String, Object?>{
        'a': 1,
        'b': 'hi',
      }, 1024);
      expect(out.truncated, isFalse);
      expect(jsonDecode(out.json), <String, Object?>{'a': 1, 'b': 'hi'});
      expect(out.bytes, utf8.encode(out.json).length);
    });

    test('fragment exactly at budget is kept', () {
      final String raw = jsonEncode(<String, Object?>{'k': 'v'});
      final int budget = utf8.encode(raw).length;
      final BudgetedJson out = encodeWithBudget(<String, Object?>{
        'k': 'v',
      }, budget);
      expect(out.truncated, isFalse);
      expect(out.json, raw);
    });
  });

  group('encodeWithBudget truncation marker', () {
    test('overflow yields PRD §11.4 marker shape', () {
      final Map<String, Object?> big = <String, Object?>{
        'payload': List<int>.filled(500, 9),
      };
      final int original = utf8.encode(jsonEncode(big)).length;
      final BudgetedJson out = encodeWithBudget(big, 32);
      expect(out.truncated, isTrue);
      final Map<String, Object?> decoded =
          jsonDecode(out.json) as Map<String, Object?>;
      expect(decoded['_truncated'], isTrue);
      expect(decoded['originalBytes'], original);
      expect(decoded['budgetBytes'], 32);
    });
  });

  group('distributeExtensionBudgets', () {
    test('defaults to 1024 per extension when not requested', () {
      final Map<String, int> eff = distributeExtensionBudgets(
        const <String, int>{},
        <String>['a', 'b'],
      );
      expect(eff['a'], 1024);
      expect(eff['b'], 1024);
      // Sum exactly hits the cap (2048), so no scaling occurs.
      final int sum = eff.values.fold<int>(0, (int x, int y) => x + y);
      expect(sum, 2048);
    });

    test('explicit overrides preserved when sum <= cap', () {
      final Map<String, int> eff = distributeExtensionBudgets(
        const <String, int>{'a': 256, 'b': 512},
        <String>['a', 'b'],
      );
      expect(eff['a'], 256);
      expect(eff['b'], 512);
    });

    test('sum > 2048 scales proportionally', () {
      // 1500 + 1500 + 1500 = 4500. scale = 2048 / 4500 ≈ 0.4551.
      // floor(1500 * scale) = 682.
      final Map<String, int> eff = distributeExtensionBudgets(
        const <String, int>{'a': 1500, 'b': 1500, 'c': 1500},
        <String>['a', 'b', 'c'],
      );
      expect(eff['a'], 682);
      expect(eff['b'], 682);
      expect(eff['c'], 682);
      expect(
        eff.values.fold<int>(0, (int x, int y) => x + y),
        lessThanOrEqualTo(2048),
      );
    });

    test('mix of requested + default still respects cap', () {
      // explicit 'a':2000, 'b' defaults to 1024 -> sum 3024 > 2048.
      final Map<String, int> eff = distributeExtensionBudgets(
        const <String, int>{'a': 2000},
        <String>['a', 'b'],
      );
      expect(
        eff.values.fold<int>(0, (int x, int y) => x + y),
        lessThanOrEqualTo(2048),
      );
    });
  });
}
