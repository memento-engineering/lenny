import 'dart:developer' as developer;

import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Once a Flutter binding is installed in a process it cannot be torn down
  // and re-installed (BindingBase asserts _debugInitializedType is null).
  // This test file uses only plain `test()` (no `testWidgets`) so the
  // LeonardBinding can be installed without conflicting with the
  // AutomatedTestWidgetsFlutterBinding the test framework would otherwise
  // auto-install.
  setUpAll(() {
    LeonardBinding.ensureInitialized(extensions: const <LeonardExtension>[]);
  });

  test('ext.exploration.core.screenshot is registered exactly once', () {
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
        'ext.exploration.core.screenshot',
        (String m, Map<String, String> p) async =>
            developer.ServiceExtensionResponse.result('{}'),
      ),
      throwsArgumentError,
    );
  });

  test('ScreenshotConfig defaults match capability matrix', () {
    expect(ScreenshotConfig.defaultEnabledForVisionModel, isTrue);
    expect(ScreenshotConfig.defaultEnabledForTextModel, isFalse);
  });
}
