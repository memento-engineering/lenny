import 'package:leonard_agent/leonard_agent.dart' show StabilityPolicy;
import 'package:leonard_cli/src/cli_args.dart';
import 'package:test/test.dart';

void main() {
  group('parseCliArgs', () {
    test('missing --vm-uri throws', () {
      expect(
        () => parseCliArgs(<String>['--goal', 'x']),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('valid parse', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'login',
        '--model',
        'claude',
        '--policy',
        'idle',
        '--extensions',
        'router,riverpod,dio',
      ]);
      expect(args.vmUri, Uri.parse('ws://127.0.0.1/ws'));
      expect(args.goal, 'login');
      expect(args.tier, ModelTier.claude);
      expect(args.policy, StabilityPolicy.quietFrame);
      expect(args.extensions, <String>['router', 'riverpod', 'dio']);
    });

    test('--goal-file parses when --goal is absent', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal-file',
        'scenarios/panel.md',
      ]);
      expect(args.goal, isNull);
      expect(args.goalFile, 'scenarios/panel.md');
    });

    test('--goal and --goal-file are mutually exclusive', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://127.0.0.1/ws',
          '--goal',
          'x',
          '--goal-file',
          'goal.md',
        ]),
        throwsA(
          isA<CliUsageError>().having(
            (error) => error.message,
            'message',
            contains('mutually exclusive'),
          ),
        ),
      );
    });

    test('repeated --action-env values are de-duplicated in order', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--action-env',
        'FIRST_NAME',
        '--action-env',
        'SECOND_NAME',
        '--action-env',
        'FIRST_NAME',
      ]);
      expect(args.actionEnvironmentNames, <String>[
        'FIRST_NAME',
        'SECOND_NAME',
      ]);
    });

    test('lowercase and dashed --action-env names are rejected', () {
      for (final String name in <String>['lowercase', 'DASHED-NAME']) {
        expect(
          () => parseCliArgs(<String>[
            '--vm-uri',
            'ws://127.0.0.1/ws',
            '--action-env',
            name,
          ]),
          throwsA(
            isA<CliUsageError>().having(
              (error) => error.message,
              'message',
              contains(name),
            ),
          ),
        );
      }
    });

    test('invalid --model rejected', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://127.0.0.1/ws',
          '--model',
          'gemini',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('--model-id parses and defaults to null', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'x',
      ]);
      expect(args.modelId, isNull);
      final withId = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'x',
        '--model',
        'qwen-mlx',
        '--model-id',
        'qwen3.8-40b-a3b-8bit',
      ]);
      expect(withId.tier, ModelTier.qwenMlx);
      expect(withId.modelId, 'qwen3.8-40b-a3b-8bit');
    });

    test('--model-id trims surrounding whitespace', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'x',
        '--model-id',
        '  qwen3.8-40b-a3b-8bit  ',
      ]);
      expect(args.modelId, 'qwen3.8-40b-a3b-8bit');
    });

    test('empty --model-id rejected', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://127.0.0.1/ws',
          '--goal',
          'x',
          '--model-id',
          '   ',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('invalid --policy rejected', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://127.0.0.1/ws',
          '--policy',
          'wat',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('extensions parsing', () {
      final empty = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
      expect(empty.extensions, isEmpty);
      final spaced = parseCliArgs(<String>[
        '--vm-uri',
        'ws://h/ws',
        '--extensions',
        ' router , dio ',
      ]);
      expect(spaced.extensions, <String>['router', 'dio']);
    });

    test('default tier is claude and policy is action-relative', () {
      final args = parseCliArgs(<String>['--vm-uri', 'ws://127.0.0.1/ws']);
      expect(args.tier, ModelTier.claude);
      expect(args.policy, StabilityPolicy.actionRelative);
    });

    test('--turn-budget 60 sets turnBudget to Duration(seconds: 60)', () {
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://h/ws',
        '--turn-budget',
        '60',
      ]);
      expect(args.turnBudget, const Duration(seconds: 60));
    });

    test('--turn-budget 0 throws CliUsageError', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://h/ws',
          '--turn-budget',
          '0',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('--turn-budget absent leaves turnBudget null', () {
      final args = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
      expect(args.turnBudget, isNull);
    });

    group('--core-budget-bytes / --probe-artifact', () {
      test('both are null when absent', () {
        final args = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
        expect(args.coreBudgetBytes, isNull);
        expect(args.probeArtifactPath, isNull);
      });

      test('parses a positive byte budget and artifact path', () {
        final args = parseCliArgs(<String>[
          '--vm-uri',
          'ws://h/ws',
          '--core-budget-bytes',
          '131072',
          '--probe-artifact',
          '/tmp/p.json',
        ]);
        expect(args.coreBudgetBytes, 131072);
        expect(args.probeArtifactPath, '/tmp/p.json');
      });

      test('rejects non-positive and non-numeric budgets', () {
        for (final String raw in <String>['0', '-1', 'lots']) {
          expect(
            () => parseCliArgs(<String>[
              '--vm-uri',
              'ws://h/ws',
              '--core-budget-bytes',
              raw,
            ]),
            throwsA(isA<CliUsageError>()),
          );
        }
      });
    });

    test('--done-reason-pattern parses and rejects an invalid regex', () {
      const String pattern =
          r'^panel smoke passed: inner turn \d+ tool [A-Za-z0-9_.]+$';
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'x',
        '--done-reason-pattern',
        pattern,
      ]);
      expect(args.doneReasonPattern, pattern);

      expect(
        () => parseCliArgs(<String>[
          '--vm-uri',
          'ws://127.0.0.1/ws',
          '--goal',
          'x',
          '--done-reason-pattern',
          '([unclosed',
        ]),
        throwsA(
          isA<CliUsageError>().having(
            (error) => error.message,
            'message',
            contains('valid regular expression'),
          ),
        ),
      );
    });

    test('--done-evidence-pattern parses and rejects bad values', () {
      const String pattern = r'^#([0-9]+) ([A-Za-z0-9_.-]+)\(';
      final args = parseCliArgs(<String>[
        '--vm-uri',
        'ws://127.0.0.1/ws',
        '--goal',
        'x',
        '--done-evidence-pattern',
        pattern,
      ]);
      expect(args.doneEvidencePattern, pattern);

      for (final String bad in <String>['', '([unclosed']) {
        expect(
          () => parseCliArgs(<String>[
            '--vm-uri',
            'ws://127.0.0.1/ws',
            '--goal',
            'x',
            '--done-evidence-pattern',
            bad,
          ]),
          throwsA(isA<CliUsageError>()),
          reason: 'accepted $bad',
        );
      }
    });

    group('--launch', () {
      test('parses with --target; vmUri is null', () {
        final args = parseCliArgs(<String>[
          '--launch',
          '--runner',
          'dart',
          '-t',
          'bin/host.dart',
          '--goal',
          'x',
        ]);
        expect(args.launch, isTrue);
        expect(args.runner, LaunchRunner.dart);
        expect(args.target, 'bin/host.dart');
        expect(args.vmUri, isNull);
      });

      test('flutter runner with device parses', () {
        final args = parseCliArgs(<String>[
          '--launch',
          '-d',
          'iPhone 15',
          '-t',
          'lib/main.dart',
        ]);
        expect(args.runner, LaunchRunner.flutter);
        expect(args.device, 'iPhone 15');
        expect(args.target, 'lib/main.dart');
      });

      test('--launch and --vm-uri together throw (mutually exclusive)', () {
        expect(
          () => parseCliArgs(<String>[
            '--launch',
            '-t',
            'lib/main.dart',
            '--vm-uri',
            'ws://h/ws',
          ]),
          throwsA(isA<CliUsageError>()),
        );
      });

      test('--launch without --target throws', () {
        expect(
          () => parseCliArgs(<String>['--launch', '--runner', 'flutter']),
          throwsA(isA<CliUsageError>()),
        );
      });

      test('--launch --runner dart with -d throws (no dual mode)', () {
        expect(
          () => parseCliArgs(<String>[
            '--launch',
            '--runner',
            'dart',
            '-t',
            'bin/host.dart',
            '-d',
            'iPhone',
          ]),
          throwsA(isA<CliUsageError>()),
        );
      });

      test('--device without --launch throws', () {
        expect(
          () => parseCliArgs(<String>['--vm-uri', 'ws://h/ws', '-d', 'iPhone']),
          throwsA(isA<CliUsageError>()),
        );
      });

      test('--target without --launch throws', () {
        expect(
          () => parseCliArgs(<String>[
            '--vm-uri',
            'ws://h/ws',
            '-t',
            'lib/main.dart',
          ]),
          throwsA(isA<CliUsageError>()),
        );
      });
    });
  });
}
