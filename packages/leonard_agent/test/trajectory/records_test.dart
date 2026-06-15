import 'package:leonard_agent/src/trajectory/records.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionManifestRecord', () {
    test('round-trips snake_case keys', () {
      const r = ExtensionManifestRecord(
        namespace: 'router',
        packageVersion: '1.2.3',
        contractVersion: '1.0.0',
      );
      expect(r.toJson(), {
        'namespace': 'router',
        'package_version': '1.2.3',
        'contract_version': '1.0.0',
      });
    });
  });

  group('SessionHeader', () {
    test('emits header type and snake_case keys with nested plugins', () {
      const h = SessionHeader(
        goal: 'login',
        agentsMdHash: 'sha256:abc',
        buildIdentifier: 'debug-1.0.0',
        modelIdentifier: 'qwen3.6-35b-a3b@8bit',
        harnessVersion: '0.1.0',
        plugins: [
          ExtensionManifestRecord(
            namespace: 'router',
            packageVersion: '1.2.3',
            contractVersion: '1.0.0',
          ),
        ],
        config: {'turn_budget_ms': 30000},
      );
      final j = h.toJson();
      expect(j['type'], 'header');
      expect(j['goal'], 'login');
      expect(j['agents_md_hash'], 'sha256:abc');
      expect(j['build_identifier'], 'debug-1.0.0');
      expect(j['model_identifier'], 'qwen3.6-35b-a3b@8bit');
      expect(j['harness_version'], '0.1.0');
      expect(j['extensions'], [
        {
          'namespace': 'router',
          'package_version': '1.2.3',
          'contract_version': '1.0.0',
        },
      ]);
      expect(j['config'], {'turn_budget_ms': 30000});
    });
  });

  group('TurnRecord', () {
    test('emits turn type and PRD §14 snake_case keys (v2 schema)', () {
      const t = TurnRecord(
        index: 3,
        observation: {
          'core': <String, dynamic>{},
          'extensions': <String, dynamic>{},
        },
        stability: {'policy': 'action_relative'},
        proposedAction: {'tool': 'core.tap'},
        validation: {'result': 'ok', 'retries': 0},
        executedAction: {'tool': 'core.tap'},
        diff: {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
        thinking: 'I should tap the button',
        modelMetadata: {'tokens_in': 10, 'tokens_out': 5, 'duration_ms': 200},
      );
      final j = t.toJson();
      expect(j['type'], 'turn');
      expect(j['index'], 3);
      expect(j['observation'], {
        'core': <String, dynamic>{},
        'extensions': <String, dynamic>{},
      });
      expect(j['stability'], {'policy': 'action_relative'});
      expect(j['proposed_action'], {'tool': 'core.tap'});
      expect(j['validation'], {'result': 'ok', 'retries': 0});
      expect(j['executed_action'], {'tool': 'core.tap'});
      expect(j['diff'], {
        'core': <String, dynamic>{},
        'extensions': <String, dynamic>{},
      });
      // v2 (lenny-wisp-cl4): summary_update key is dropped from JSON;
      // thinking takes its place.
      expect(j.containsKey('summary_update'), isFalse);
      expect(j['thinking'], 'I should tap the button');
      expect(j['model_metadata'], {
        'tokens_in': 10,
        'tokens_out': 5,
        'duration_ms': 200,
      });
    });

    test('toJson omits thinking key when null or empty (v2 schema)', () {
      const tNull = TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{},
        validation: <String, dynamic>{'ok': true},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        modelMetadata: <String, dynamic>{},
      );
      expect(tNull.toJson().containsKey('thinking'), isFalse);

      const tEmpty = TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{},
        validation: <String, dynamic>{'ok': true},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        thinking: '',
        modelMetadata: <String, dynamic>{},
      );
      expect(tEmpty.toJson().containsKey('thinking'), isFalse);
    });

    test('fromJson tolerantly ignores legacy summary_update key', () {
      // The summary_update key is no longer part of the schema; fromJson
      // must still accept v1 records carrying it (the key is ignored).
      final TurnRecord rec = TurnRecord.fromJson(<String, dynamic>{
        'type': 'turn',
        'index': 1,
        'observation': <String, dynamic>{},
        'stability': <String, dynamic>{},
        'proposed_action': <String, dynamic>{},
        'validation': <String, dynamic>{},
        'executed_action': <String, dynamic>{},
        'diff': <String, dynamic>{},
        'summary_update': 'legacy text',
        'model_metadata': <String, dynamic>{},
      });
      expect(rec.thinking, isNull);
    });
  });

  group('TurnRecord.providerRequestId', () {
    test('round-trips provider_request_id', () {
      const rec = TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{'tool': 'core.tap'},
        validation: <String, dynamic>{'ok': true},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        modelMetadata: <String, dynamic>{},
        providerRequestId: 'msg_5C16E942855',
      );
      final j = rec.toJson();
      expect(j['provider_request_id'], 'msg_5C16E942855');
      final back = TurnRecord.fromJson(j);
      expect(back.providerRequestId, 'msg_5C16E942855');
    });

    test('omits provider_request_id when null', () {
      const rec = TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{},
        validation: <String, dynamic>{'ok': true},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        modelMetadata: <String, dynamic>{},
      );
      expect(rec.toJson().containsKey('provider_request_id'), isFalse);
    });
  });

  group('ExtensionDisabledEvent', () {
    test('emits extension_disabled type with namespace, reason, turn', () {
      const e = ExtensionDisabledEvent(
        namespace: 'dio',
        reason: 'auto_disabled_after_3_failures',
        turn: 7,
      );
      expect(e.toJson(), {
        'type': 'extension_disabled',
        'namespace': 'dio',
        'reason': 'auto_disabled_after_3_failures',
        'turn': 7,
      });
    });
  });

  group('SessionFooter', () {
    test(
      'budgetExhausted -> budget_exhausted; harnessError omitted when null (v2 schema)',
      () {
        const f = SessionFooter(
          outcome: SessionOutcome.budgetExhausted,
          totalTurns: 25,
          totalDurationMs: 30000,
        );
        final j = f.toJson();
        expect(j['type'], 'footer');
        expect(j['outcome'], 'budget_exhausted');
        // v2 (lenny-wisp-cl4): final_summary key is dropped from JSON.
        expect(j.containsKey('final_summary'), isFalse);
        expect(j['total_turns'], 25);
        expect(j['total_duration_ms'], 30000);
        expect(j.containsKey('harness_error'), isFalse);
      },
    );

    test('done outcome maps to "done"', () {
      const f = SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 12,
        totalDurationMs: 12000,
      );
      expect(f.toJson()['outcome'], 'done');
    });

    test('harnessError outcome includes harness_error key', () {
      const f = SessionFooter(
        outcome: SessionOutcome.harnessError,
        totalTurns: 4,
        totalDurationMs: 5000,
        harnessError: 'connection_lost',
      );
      final j = f.toJson();
      expect(j['outcome'], 'harness_error');
      expect(j['harness_error'], 'connection_lost');
    });
  });
}
