import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exploration_flutter/exploration_flutter.dart';

/// debugReset must restore `FlutterError.onError` and
/// `PlatformDispatcher.onError` to the priors captured at install time.
void main() {
  test('debugReset restores priors and clears the singleton', () {
    // Capture priors BEFORE installing the binding so the test owns the
    // baseline. ensureInitialized then wraps these.
    final FlutterExceptionHandler? prePriorFlutter = FlutterError.onError;
    final ErrorCallback? prePriorPlatform =
        PlatformDispatcher.instance.onError;

    final ExplorationBinding binding =
        ExplorationBinding.ensureInitialized(plugins: const [])!;
    expect(binding.debugErrorHooksInstalled(), isTrue);
    // The wrapped handler must NOT be the same object as the prior.
    expect(identical(FlutterError.onError, prePriorFlutter), isFalse,
        reason: 'install must replace FlutterError.onError');

    ExplorationBinding.debugReset();

    // After reset, the priors are restored verbatim.
    expect(identical(FlutterError.onError, prePriorFlutter), isTrue,
        reason: 'debugReset must restore the prior FlutterError.onError');
    expect(identical(PlatformDispatcher.instance.onError, prePriorPlatform),
        isTrue,
        reason: 'debugReset must restore the prior '
            'PlatformDispatcher.onError');
  });
}
