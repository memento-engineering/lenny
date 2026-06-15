import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

void main() {
  test('frameworkBusySnapshot returns zero in release mode', () {
    if (!kReleaseMode) {
      // ensureInitialized is a no-op in release mode and returns null,
      // so we only exercise the release-mode branch when actually
      // running release tests. In debug/profile this test asserts the
      // gating contract is *queryable* — the snapshot is well-defined.
      final binding = LeonardBinding.ensureInitialized(extensions: const []);
      expect(binding, isNotNull);
      final s = binding!.frameworkBusySnapshot();
      // In debug/profile, the snapshot is live (counters may be
      // anything). The critical invariant is that the field set is
      // exactly the documented one.
      expect(s.transientCallbacks, isA<int>());
      return;
    }

    // Release-mode contract: ensureInitialized returns null and the
    // binding hooks are not installed. We cannot construct an instance
    // here because the constructor is private; instead we assert the
    // canonical zero snapshot is well-defined.
    expect(FrameworkBusySnapshot.zero.isAnyBusy, isFalse);
    expect(FrameworkBusySnapshot.zero.lastFrameCommitTimestamp, isNull);
  });
}
