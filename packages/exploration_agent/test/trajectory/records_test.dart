import 'package:exploration_agent/src/trajectory/records.dart';
import 'package:test/test.dart';

void main() {
  group('PluginManifestRecord', () {
    test('round-trips snake_case keys', () {
      const r = PluginManifestRecord(
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
          PluginManifestRecord(
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
      expect(j['plugins'], [
        {
          'namespace': 'router',
          'package_version': '1.2.3',
          'contract_version': '1.0.0',
        }
      ]);
      expect(j['config'], {'turn_budget_ms': 30000});
    });
  });

  group('TurnRecord', () {
    test('emits turn type and PRD §14 snake_case keys', () {
      const t = TurnRecord(
        index: 3,
        observation: {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}},
        stability: {'policy': 'action_relative'},
        proposedAction: {'tool': 'core.tap'},
        validation: {'result': 'ok', 'retries': 0},
        executedAction: {'tool': 'core.tap'},
        diff: {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}},
        summaryUpdate: 'tapped',
        modelMetadata: {
          'tokens_in': 10,
          'tokens_out': 5,
          'duration_ms': 200,
        },
      );
      final j = t.toJson();
      expect(j['type'], 'turn');
      expect(j['index'], 3);
      expect(j['observation'], {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}});
      expect(j['stability'], {'policy': 'action_relative'});
      expect(j['proposed_action'], {'tool': 'core.tap'});
      expect(j['validation'], {'result': 'ok', 'retries': 0});
      expect(j['executed_action'], {'tool': 'core.tap'});
      expect(j['diff'], {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}});
      expect(j['summary_update'], 'tapped');
      expect(j['model_metadata'], {
        'tokens_in': 10,
        'tokens_out': 5,
        'duration_ms': 200,
      });
    });
  });

  group('PluginDisabledEvent', () {
    test('emits plugin_disabled type with namespace, reason, turn', () {
      const e = PluginDisabledEvent(
        namespace: 'dio',
        reason: 'auto_disabled_after_3_failures',
        turn: 7,
      );
      expect(e.toJson(), {
        'type': 'plugin_disabled',
        'namespace': 'dio',
        'reason': 'auto_disabled_after_3_failures',
        'turn': 7,
      });
    });
  });

  group('SessionFooter', () {
    test('budgetExhausted -> budget_exhausted; harnessError omitted when null',
        () {
      const f = SessionFooter(
        outcome: SessionOutcome.budgetExhausted,
        finalSummary: 'ran out of turns',
        totalTurns: 25,
        totalDurationMs: 30000,
      );
      final j = f.toJson();
      expect(j['type'], 'footer');
      expect(j['outcome'], 'budget_exhausted');
      expect(j['final_summary'], 'ran out of turns');
      expect(j['total_turns'], 25);
      expect(j['total_duration_ms'], 30000);
      expect(j.containsKey('harness_error'), isFalse);
    });

    test('done outcome maps to "done"', () {
      const f = SessionFooter(
        outcome: SessionOutcome.done,
        finalSummary: 'goal achieved',
        totalTurns: 12,
        totalDurationMs: 12000,
      );
      expect(f.toJson()['outcome'], 'done');
    });

    test('harnessError outcome includes harness_error key', () {
      const f = SessionFooter(
        outcome: SessionOutcome.harnessError,
        finalSummary: 'crashed',
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
