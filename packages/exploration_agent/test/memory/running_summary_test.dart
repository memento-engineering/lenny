import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

/// Test counter that returns whatever count is associated with the
/// most-recently-passed string. Lets tests pin behaviour at the cap
/// boundaries without caring about the actual tokenizer.
class _FakeCounter implements TokenCounter {
  _FakeCounter(this._counts);
  final Map<String, int> _counts;

  @override
  int count(String text) {
    final int? n = _counts[text];
    if (n == null) {
      throw StateError('No fake count registered for "$text"');
    }
    return n;
  }
}

void main() {
  group('RunningSummary', () {
    test('initial state: text is empty, softCapExceeded is false', () {
      final RunningSummary s =
          RunningSummary(counter: _FakeCounter(<String, int>{}));
      expect(s.text, '');
      expect(s.softCapExceeded, isFalse);
    });

    test('update with 0 tokens leaves softCapExceeded false', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{'': 0}),
      );
      s.update('');
      expect(s.text, '');
      expect(s.softCapExceeded, isFalse);
    });

    test('update at exactly soft cap leaves softCapExceeded false', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{'a': 500}),
      );
      s.update('a');
      expect(s.text, 'a');
      expect(s.softCapExceeded, isFalse);
    });

    test('update at soft cap + 1 sets softCapExceeded true', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{'b': 501}),
      );
      s.update('b');
      expect(s.text, 'b');
      expect(s.softCapExceeded, isTrue);
    });

    test('update at exactly hard cap is accepted', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{'c': 1000}),
      );
      s.update('c');
      expect(s.text, 'c');
      expect(s.softCapExceeded, isTrue);
    });

    test('update above hard cap throws SummaryOversizeError', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{'d': 1001}),
      );
      expect(
        () => s.update('d'),
        throwsA(
          isA<SummaryOversizeError>()
              .having((SummaryOversizeError e) => e.tokenCount,
                  'tokenCount', 1001)
              .having((SummaryOversizeError e) => e.cap, 'cap', 1000),
        ),
      );
    });

    test('oversize update preserves prior summary', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{
          'first': 100,
          'huge': 5000,
        }),
      );
      s.update('first');
      expect(() => s.update('huge'), throwsA(isA<SummaryOversizeError>()));
      expect(s.text, 'first');
      expect(s.softCapExceeded, isFalse);
    });

    test('custom caps are respected', () {
      final RunningSummary s = RunningSummary(
        counter: _FakeCounter(<String, int>{
          'a': 9,
          'b': 11,
          'c': 21,
        }),
        softCap: 10,
        hardCap: 20,
      );
      s.update('a');
      expect(s.softCapExceeded, isFalse);
      s.update('b');
      expect(s.softCapExceeded, isTrue);
      expect(
        () => s.update('c'),
        throwsA(
          isA<SummaryOversizeError>()
              .having((SummaryOversizeError e) => e.cap, 'cap', 20),
        ),
      );
    });

    test('SummaryOversizeError.toString includes count + cap', () {
      final SummaryOversizeError e =
          SummaryOversizeError(tokenCount: 1500, cap: 1000);
      expect(e.toString(), contains('1500'));
      expect(e.toString(), contains('1000'));
    });
  });
}
