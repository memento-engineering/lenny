import 'package:leonard_contract/src/strike_counter.dart';
import 'package:test/test.dart';

void main() {
  test('trips at the limit and remains tripped past it', () {
    final counter = StrikeCounter(limit: 3);

    counter.recordFailure();
    expect(counter.isTripped, isFalse);
    counter.recordFailure();
    expect(counter.isTripped, isFalse);
    counter.recordFailure();
    expect(counter.isTripped, isTrue);
    counter.recordFailure();
    expect(counter.isTripped, isTrue);
  });

  test('success resets the consecutive failure count', () {
    final counter = StrikeCounter(limit: 3);

    counter.recordFailure();
    counter.recordFailure();
    counter.recordSuccess();

    expect(counter.isTripped, isFalse);
    counter.recordFailure();
    expect(counter.isTripped, isFalse);
    counter.recordFailure();
    expect(counter.isTripped, isFalse);
    counter.recordFailure();
    expect(counter.isTripped, isTrue);
  });
}
