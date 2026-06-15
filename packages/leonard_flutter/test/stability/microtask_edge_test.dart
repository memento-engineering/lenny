import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

void main() {
  late LeonardBinding binding;

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(extensions: const [])!;
  });

  test(
    'pendingMicrotasks flips true after scheduleMicrotask in zone',
    () async {
      expect(binding.frameworkBusySnapshot().pendingMicrotasks, isFalse);

      // Run inside the stability zone so the binding can intercept the
      // scheduleMicrotask call. Outside this zone, the microtask edge
      // signal is intentionally inert (the zone is installed for
      // production via LeonardBinding.installAndRun).
      await runZoned<Future<void>>(() async {
        scheduleMicrotask(() {});
        // Read synchronously before yielding so the microtask has not yet
        // run.
        expect(binding.frameworkBusySnapshot().pendingMicrotasks, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(binding.frameworkBusySnapshot().pendingMicrotasks, isFalse);
      }, zoneSpecification: LeonardBinding.stabilityZoneSpec(binding));
    },
  );

  test('markMicrotaskScheduled flips edge directly (no zone)', () async {
    // Independent of the ZoneSpecification path, the underlying mixin
    // method is the source of truth and must produce the same edge.
    expect(binding.frameworkBusySnapshot().pendingMicrotasks, isFalse);
    binding.markMicrotaskScheduled();
    expect(binding.frameworkBusySnapshot().pendingMicrotasks, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(binding.frameworkBusySnapshot().pendingMicrotasks, isFalse);
  });
}
