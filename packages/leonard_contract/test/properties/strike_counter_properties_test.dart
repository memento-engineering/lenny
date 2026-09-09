import 'package:glados/glados.dart';
import 'package:leonard_contract/src/strike_counter.dart';

void main() {
  Glados2<int, List<bool>>(
    any.intInRange(1, 9),
    any.listWithLengthInRange<bool>(0, 65, any.bool),
  ).test(
    'is tripped exactly for a trailing run at least as long as the limit',
    (int limit, List<bool> events) {
      final StrikeCounter counter = StrikeCounter(limit: limit);
      var trailingFailures = 0;

      expect(counter.isTripped, trailingFailures >= limit);
      for (final bool isFailure in events) {
        if (isFailure) {
          counter.recordFailure();
          trailingFailures++;
        } else {
          counter.recordSuccess();
          trailingFailures = 0;
        }

        expect(
          counter.isTripped,
          trailingFailures >= limit,
          reason: 'limit=$limit, trailingFailures=$trailingFailures',
        );
      }
    },
  );
}
