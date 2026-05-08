import 'package:exploration_agent/exploration_agent.dart' show StabilityPolicy;
import 'package:exploration_cli/src/cli_args.dart';
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
        '--plugins', 'router,riverpod,dio',
      ]);
      expect(args.vmUri, Uri.parse('ws://127.0.0.1/ws'));
      expect(args.goal, 'login');
      expect(args.tier, ModelTier.claude);
      expect(args.policy, StabilityPolicy.quietFrame);
      expect(args.plugins, <String>['router', 'riverpod', 'dio']);
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

    test('plugins parsing', () {
      final empty = parseCliArgs(<String>['--vm-uri', 'ws://h/ws']);
      expect(empty.plugins, isEmpty);
      final spaced = parseCliArgs(<String>[
        '--vm-uri', 'ws://h/ws',
        '--plugins', ' router , dio ',
      ]);
      expect(spaced.plugins, <String>['router', 'dio']);
    });

    test('default tier is qwen-mlx and policy is action-relative', () {
      final args = parseCliArgs(<String>[
        '--vm-uri', 'ws://127.0.0.1/ws',
      ]);
      expect(args.tier, ModelTier.qwenMlx);
      expect(args.policy, StabilityPolicy.actionRelative);
    });
  });
}
