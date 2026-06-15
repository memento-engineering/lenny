import 'package:leonard_devtools/src/conversation/conversation_state.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationState', () {
    test('default state has idle status and empty entries', () {
      const state = ConversationState();
      expect(state.status, RunStatus.idle);
      expect(state.entries, isEmpty);
      expect(state.currentTurn, -1);
      expect(state.maxTurns, isNull);
      expect(state.usage, isNull);
      expect(state.startedAt, isNull);
    });

    test('copyWith replaces individual fields', () {
      const state = ConversationState();
      final updated = state.copyWith(
        status: RunStatus.running,
        currentTurn: 2,
        maxTurns: 10,
      );
      expect(updated.status, RunStatus.running);
      expect(updated.currentTurn, 2);
      expect(updated.maxTurns, 10);
      expect(updated.entries, isEmpty);
    });

    test('UsageSnapshot copyWith', () {
      const snap = UsageSnapshot(estimatedTokens: 100);
      final updated = snap.copyWith(estimatedTokens: 200, trimThreshold: 8000);
      expect(updated.estimatedTokens, 200);
      expect(updated.trimThreshold, 8000);
    });

    test('copyWith preserves startedAt', () {
      final t = DateTime.utc(2026, 1, 1);
      final state = ConversationState(startedAt: t);
      expect(state.copyWith(status: RunStatus.running).startedAt, t);
    });

    test('ConversationEntry copyWith with sentinel for nullable toolArgs', () {
      const entry = ConversationEntry(turnIndex: 0, toolArgs: {'a': 1});
      // Omitting toolArgs keeps the original.
      final withNewName = entry.copyWith(toolName: 'core.tap');
      expect(withNewName.toolArgs, {'a': 1});

      // Explicitly passing null clears it.
      final cleared = entry.copyWith(toolArgs: null);
      expect(cleared.toolArgs, isNull);
    });
  });
}
