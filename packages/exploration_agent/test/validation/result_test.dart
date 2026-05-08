import 'dart:convert';

import 'package:exploration_agent/src/validation/result.dart';
import 'package:test/test.dart';

void main() {
  group('ValidationOk', () {
    test('all instances are equal', () {
      expect(const ValidationOk(), equals(const ValidationOk()));
    });
  });

  group('ValidationReject.toModelMessage', () {
    test('emits single-line JSON with all populated fields', () {
      const r = ValidationReject(
        tool: 'core.tap',
        reason: 'node_not_found',
        pointer: '/node_id',
        got: 42,
        description: 'node_id=42 is not present',
      );
      final msg = r.toModelMessage();
      expect(msg, isNot(contains('\n')));

      final decoded = jsonDecode(msg) as Map<String, dynamic>;
      expect(decoded['tool'], 'core.tap');
      expect(decoded['reason'], 'node_not_found');
      expect(decoded['pointer'], '/node_id');
      expect(decoded['got'], 42);
      expect(decoded['description'], 'node_id=42 is not present');
    });

    test('omits keys whose values are null', () {
      const r = ValidationReject(
        tool: 'foo.bar',
        reason: 'unknown_tool',
      );
      final decoded =
          jsonDecode(r.toModelMessage()) as Map<String, dynamic>;
      expect(decoded.keys, unorderedEquals(<String>['tool', 'reason']));
      expect(decoded.containsKey('expected'), isFalse);
      expect(decoded.containsKey('got'), isFalse);
      expect(decoded.containsKey('pointer'), isFalse);
      expect(decoded.containsKey('description'), isFalse);
    });

    test('expected list survives JSON round-trip', () {
      const r = ValidationReject(
        tool: 'unknown',
        reason: 'unknown_tool',
        expected: <String>['core.tap', 'core.long_press'],
        got: 'unknown',
      );
      final decoded =
          jsonDecode(r.toModelMessage()) as Map<String, dynamic>;
      expect(decoded['expected'],
          equals(<String>['core.tap', 'core.long_press']));
      expect(decoded['got'], 'unknown');
    });

    test('value-equal rejects compare equal', () {
      const a = ValidationReject(
        tool: 'core.tap',
        reason: 'node_disabled',
        pointer: '/node_id',
        got: 7,
        description: 'disabled',
      );
      const b = ValidationReject(
        tool: 'core.tap',
        reason: 'node_disabled',
        pointer: '/node_id',
        got: 7,
        description: 'disabled',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('sealed exhaustiveness', () {
    String describe(ValidationResult r) {
      return switch (r) {
        ValidationOk() => 'ok',
        ValidationReject(:final reason) => 'reject:$reason',
      };
    }

    test('switch covers both variants', () {
      expect(describe(const ValidationOk()), 'ok');
      expect(
        describe(const ValidationReject(
          tool: 't',
          reason: 'unknown_tool',
        )),
        'reject:unknown_tool',
      );
    });
  });
}
