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
        '--vm-uri', 'ws://127.0.0.1/ws',
        '--goal', 'login',
        '--model', 'claude',
        '--policy', 'idle',
        '--extensions', 'router,riverpod,dio',
      ]);
      expect(args.vmUri, Uri.parse('ws://127.0.0.1/ws'));
      expect(args.goal, 'login');
      expect(args.tier, ModelTier.claude);
      expect(args.policy, StabilityPolicy.quietFrame);
      expect(args.extensions, <String>['router', 'riverpod', 'dio']);
    });

    test('invalid --model rejected', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri', 'ws://127.0.0.1/ws',
          '--model', 'gemini',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('invalid --policy rejected', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri', 'ws://127.0.0.1/ws',
          '--policy', 'wat',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('extensions parsing', () {
      final empty = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
      expect(empty.extensions, isEmpty);
      final spaced = parseCliArgs(<String>[
        '--vm-uri', 'ws://h/ws',
        '--extensions', ' router , dio ',
      ]);
      expect(spaced.extensions, <String>['router', 'dio']);
    });

    test('default tier is claude and policy is action-relative', () {
      final args = parseCliArgs(<String>[
        '--vm-uri', 'ws://127.0.0.1/ws',
      ]);
      expect(args.tier, ModelTier.claude);
      expect(args.policy, StabilityPolicy.actionRelative);
    });

    test('--turn-budget 60 sets turnBudget to Duration(seconds: 60)', () {
      final args = parseCliArgs(<String>[
        '--vm-uri', 'ws://h/ws',
        '--turn-budget', '60',
      ]);
      expect(args.turnBudget, const Duration(seconds: 60));
    });

    test('--turn-budget 0 throws CliUsageError', () {
      expect(
        () => parseCliArgs(<String>[
          '--vm-uri', 'ws://h/ws',
          '--turn-budget', '0',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('--turn-budget absent leaves turnBudget null', () {
      final args = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
      expect(args.turnBudget, isNull);
    });
  });
}
