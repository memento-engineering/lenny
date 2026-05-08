import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

void main() {
  group('ActionRing', () {
    test('entries is empty before any push and does not throw', () {
      final ActionRing r = ActionRing();
      expect(r.entries, isEmpty);
    });

    test('push appends in insertion order while under capacity', () {
      final ActionRing r = ActionRing();
      r.push('a');
      r.push('b');
      r.push('c');
      expect(r.entries, <String>['a', 'b', 'c']);
    });

    test('push drops oldest once at capacity (default 5)', () {
      final ActionRing r = ActionRing();
      for (final String e in <String>['a', 'b', 'c', 'd', 'e', 'f']) {
        r.push(e);
      }
      expect(r.entries, <String>['b', 'c', 'd', 'e', 'f']);
    });

    test('after capacity + k pushes returns last `capacity` in order', () {
      final ActionRing r = ActionRing(capacity: 3);
      for (final String e in <String>['1', '2', '3', '4', '5', '6', '7']) {
        r.push(e);
      }
      expect(r.entries, <String>['5', '6', '7']);
    });

    test('entries view is unmodifiable', () {
      final ActionRing r = ActionRing();
      r.push('x');
      expect(() => r.entries.add('y'), throwsUnsupportedError);
    });

    test('configurable capacity', () {
      final ActionRing r = ActionRing(capacity: 1);
      r.push('a');
      r.push('b');
      expect(r.entries, <String>['b']);
    });
  });
}
