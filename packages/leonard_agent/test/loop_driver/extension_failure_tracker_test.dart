import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionFailureTracker', () {
    test('first two failures return false; third returns true', () {
      final t = ExtensionFailureTracker();
      expect(t.recordFailure('router'), isFalse);
      expect(t.recordFailure('router'), isFalse);
      expect(t.recordFailure('router'), isTrue);
      expect(t.failuresFor('router'), 3);
    });

    test('success between failures resets the counter', () {
      final t = ExtensionFailureTracker();
      t.recordFailure('router');
      t.recordFailure('router');
      t.recordSuccess('router');
      expect(t.failuresFor('router'), 0);
      expect(t.recordFailure('router'), isFalse); // back to count=1
      expect(t.failuresFor('router'), 1);
    });

    test('namespaces are tracked independently', () {
      final t = ExtensionFailureTracker();
      t.recordFailure('router');
      t.recordFailure('router');
      // 'mocks' has its own counter — not affected by router's failures.
      expect(t.recordFailure('mocks'), isFalse);
      expect(t.failuresFor('router'), 2);
      expect(t.failuresFor('mocks'), 1);
    });

    test('autoDisableThreshold matches PRD §17 (=3)', () {
      expect(ExtensionFailureTracker.autoDisableThreshold, 3);
    });
  });
}
