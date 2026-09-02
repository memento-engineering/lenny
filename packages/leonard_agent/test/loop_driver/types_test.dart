import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('TurnTimeoutError', () {
    test('toString includes turn index', () {
      expect(const TurnTimeoutError(7).toString(), contains('turn=7'));
    });
  });

  group('TurnFailure', () {
    test('toString includes turn index and reason', () {
      const f = TurnFailure(3, 'turn_timeout');
      expect(f.toString(), contains('turn=3'));
      expect(f.toString(), contains('turn_timeout'));
    });
  });

  group('SessionTermination', () {
    test('value equality on identical fields', () {
      const a = SessionTermination(
        SessionOutcome.harnessError,
        harnessError: HarnessError.agentStuck,
      );
      const b = SessionTermination(
        SessionOutcome.harnessError,
        harnessError: HarnessError.agentStuck,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('finalSummary participates in equality', () {
      const a = SessionTermination(
        SessionOutcome.done,
        finalSummary: 'reached login',
      );
      const b = SessionTermination(
        SessionOutcome.done,
        finalSummary: 'reached login',
      );
      const c = SessionTermination(
        SessionOutcome.done,
        finalSummary: 'something else',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('HarnessError', () {
    test('wireName matches PRD §14 schema', () {
      expect(HarnessError.agentStuck.wireName, 'agent_stuck');
      expect(HarnessError.connectionLost.wireName, 'connection_lost');
      expect(
        HarnessError.observationEnvelopeRejected.wireName,
        'observation_envelope_rejected',
      );
      expect(HarnessError.unclassified.wireName, 'unclassified');
    });

    test('every HarnessError value has a non-empty wire name', () {
      for (final HarnessError e in HarnessError.values) {
        expect(e.wireName, isNotEmpty, reason: 'missing wire name for $e');
      }
    });
  });
}
