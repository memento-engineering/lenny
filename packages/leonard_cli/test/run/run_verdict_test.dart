import 'dart:convert' show utf8;

import 'package:leonard_agent/leonard_agent.dart'
    show SessionFooter, SessionOutcome, TurnRecord;
import 'package:leonard_cli/src/run_verdict.dart';
import 'package:test/test.dart';

void main() {
  group('judgeRun', () {
    RunJudgement judge(
      SessionFooter? footer, {
      int exitCode = 0,
      List<TurnRecord> turns = const <TurnRecord>[],
    }) => judgeRun(exitCode: exitCode, footer: footer, turns: turns);

    test('done passes and carries the core.done reason', () {
      final RunJudgement j = judge(
        _footer(SessionOutcome.done, turns: 3),
        turns: <TurnRecord>[
          _turn(0, 'core.tap', <String, dynamic>{'node_id': '4'}),
          _turn(1, 'core.done', <String, dynamic>{
            'reason': 'Settings screen is open',
          }),
        ],
      );
      expect(j.verdict, RunVerdict.pass);
      expect(j.reason, 'goal reached in 3 turns: Settings screen is open');
    });

    test('done with a golden mismatch exit fails', () {
      final RunJudgement j = judge(_footer(SessionOutcome.done), exitCode: 1);
      expect(j.verdict, RunVerdict.fail);
      expect(j.reason, contains('golden'));
    });

    test('done with goldens that could not be compared is infra', () {
      final RunJudgement j = judge(_footer(SessionOutcome.done), exitCode: 70);
      expect(j.verdict, RunVerdict.infra);
      expect(j.reason, contains('could not be compared'));
    });

    test('budget exhausted fails, unless the model was too slow', () {
      expect(
        judge(_footer(SessionOutcome.budgetExhausted, turns: 50)).verdict,
        RunVerdict.fail,
      );
      expect(
        judge(
          _footer(SessionOutcome.budgetExhausted, detail: 'inference_latency'),
        ).verdict,
        RunVerdict.infra,
      );
    });

    test('a lost connection fails mid-drive and is infra before it', () {
      final RunJudgement midDrive = judge(
        _footer(
          SessionOutcome.harnessError,
          harnessError: 'connection_lost',
          turns: 4,
        ),
        exitCode: 1,
      );
      expect(midDrive.verdict, RunVerdict.fail);
      expect(midDrive.reason, contains('after 4 turns'));

      final RunJudgement noAttach = judge(
        _footer(SessionOutcome.harnessError, harnessError: 'connection_lost'),
        exitCode: 1,
      );
      expect(noAttach.verdict, RunVerdict.infra);
      expect(noAttach.reason, contains('[connection_lost]'));
    });

    test('every other harness error is infra and names its code', () {
      for (final String code in <String>[
        'config_error',
        'agent_stuck',
        'observation_envelope_rejected',
        'unclassified',
      ]) {
        final RunJudgement j = judge(
          _footer(
            SessionOutcome.harnessError,
            harnessError: code,
            turns: 3,
            detail: 'provider_transport: ClientException',
          ),
          exitCode: 1,
        );
        expect(j.verdict, RunVerdict.infra, reason: code);
        expect(
          j.reason,
          endsWith('[$code] (provider_transport: ClientException)'),
          reason: code,
        );
      }
    });

    test('no footer is infra, and says so for a usage error', () {
      expect(judge(null, exitCode: 64).reason, contains('usage error'));
      expect(judge(null, exitCode: 1).verdict, RunVerdict.infra);
    });

    test('gate exit codes follow the Gas City check protocol', () {
      expect(RunVerdict.pass.gateExitCode, 0);
      expect(RunVerdict.fail.gateExitCode, 1);
      expect(RunVerdict.infra.gateExitCode, 75);
    });
  });

  group('digestTurns', () {
    test('one line per turn, with errors and the last rationale', () {
      final List<String> digest = digestTurns(<TurnRecord>[
        _turn(0, 'core.tap', <String, dynamic>{'node_id': '4'}),
        _turn(1, 'core.enter_text', <String, dynamic>{
          'node_id': '5',
          'text': 'a\nb',
        }, error: 'node 5 is not editable'),
        _failedTurn(2, 'schema_exhausted'),
        _turn(3, 'core.done', <String, dynamic>{
          'reason': 'signed in',
        }, rationale: 'Home is showing'),
      ]);
      expect(digest, <String>[
        '#0 core.tap node_id="4" → ok',
        '#1 core.enter_text node_id="5" text="a b" → error: "node 5 is not '
            'editable"',
        '#2 no action (schema_exhausted)',
        '#3 core.done reason="signed in" → ok — Home is showing',
      ]);
    });

    test('drops the oldest turns to fit the budget and says how many', () {
      final List<TurnRecord> turns = <TurnRecord>[
        for (var i = 0; i < 40; i++)
          _turn(i, 'core.scroll', <String, dynamic>{'direction': 'down'}),
      ];
      final List<String> digest = digestTurns(turns, byteBudget: 200);
      expect(digest.first, startsWith('… '));
      expect(digest.last, startsWith('#39 '));
      final int kept = digest.length - 1;
      expect(digest.first, '… ${40 - kept} earlier turns omitted');
      // The omitted line counts against the budget, in UTF-8 bytes.
      expect(utf8.encode(digest.join('\n')).length, lessThan(200));
    });

    test('budgets multi-byte text in bytes, not characters', () {
      final List<TurnRecord> turns = <TurnRecord>[
        for (var i = 0; i < 40; i++)
          _turn(i, 'core.enter_text', <String, dynamic>{'text': '日本語のテキスト'}),
      ];
      final List<String> digest = digestTurns(turns, byteBudget: 300);
      expect(digest.last, startsWith('#39 '));
      expect(utf8.encode(digest.join('\n')).length, lessThan(300));
    });

    test('clips a long line', () {
      final List<String> digest = digestTurns(<TurnRecord>[
        _turn(0, 'core.enter_text', <String, dynamic>{'text': 'x' * 500}),
      ]);
      expect(digest.single.length, kDigestLineLimit);
      expect(digest.single, endsWith('…'));
    });
  });
}

SessionFooter _footer(
  SessionOutcome outcome, {
  int turns = 0,
  String? harnessError,
  String? detail,
}) => SessionFooter(
  outcome: outcome,
  totalTurns: turns,
  totalDurationMs: 1000,
  harnessError: harnessError,
  terminationDetail: detail,
);

TurnRecord _turn(
  int index,
  String tool,
  Map<String, dynamic> args, {
  String? error,
  String? rationale,
}) => TurnRecord(
  index: index,
  observation: const <String, dynamic>{},
  stability: const <String, dynamic>{},
  proposedAction: <String, dynamic>{'tool': tool, 'args': args},
  validation: const <String, dynamic>{'ok': true, 'retries': 0},
  executedAction: <String, dynamic>{
    'tool': tool,
    'args': args,
    'result': <String, dynamic>{'ok': error == null, 'error': error},
  },
  diff: const <String, dynamic>{},
  modelMetadata: <String, dynamic>{'rationale': ?rationale},
);

TurnRecord _failedTurn(int index, String reason) => TurnRecord(
  index: index,
  observation: const <String, dynamic>{},
  stability: const <String, dynamic>{},
  proposedAction: const <String, dynamic>{},
  validation: <String, dynamic>{'ok': false, 'reason': reason},
  executedAction: const <String, dynamic>{},
  diff: const <String, dynamic>{},
  modelMetadata: const <String, dynamic>{},
);
