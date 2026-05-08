import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

void main() {
  group('WhitespaceTokenCounter', () {
    const TokenCounter counter = WhitespaceTokenCounter();

    test('empty string returns 0', () {
      expect(counter.count(''), 0);
    });

    test('whitespace-only string returns 0', () {
      expect(counter.count('   \t\n '), 0);
    });

    test('single word returns 1', () {
      expect(counter.count('hello'), 1);
    });

    test('multiple words split on whitespace', () {
      expect(counter.count('hello world foo bar'), 4);
    });

    test('trailing/leading whitespace is ignored', () {
      expect(counter.count('  hello world  '), 2);
    });

    test('runs of whitespace count as a single separator', () {
      expect(counter.count('hello   world\t\tfoo\nbar'), 4);
    });
  });
}
