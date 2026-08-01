import 'dart:convert';

import 'package:leonard_flutter/src/observation/budgeted_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
