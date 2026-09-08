import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart'
    show LeonardBinding, LeonardExtension, ScreenshotConfig;
import 'package:leonard_flutter/src/screenshot_extension.dart'
    show
        ScreenshotResult,
        ScreenshotUnavailable,
        screenshotServiceExtensionResponse;

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

  test('ext.leonard.core.screenshot is registered exactly once', () {
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
        'ext.leonard.core.screenshot',
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

  test('ScreenshotResult keeps the exact four-key JSON shape', () async {
    final developer.ServiceExtensionResponse response =
        await screenshotServiceExtensionResponse(
          capture: () async => ScreenshotResult(
            pngBase64: 'png-data',
            widthPx: 12,
            heightPx: 34,
            devicePixelRatio: 2.5,
          ),
        );

    expect(response.errorCode, isNull);
    expect(jsonDecode(response.result!), <String, dynamic>{
      'result': <String, dynamic>{
        'png_base64': 'png-data',
        'width_px': 12,
        'height_px': 34,
        'device_pixel_ratio': 2.5,
      },
    });
  });

  test(
    'ScreenshotUnavailable keeps the code-1 extension error shape',
    () async {
      final developer.ServiceExtensionResponse response =
          await screenshotServiceExtensionResponse(
            capture: () async {
              throw const ScreenshotUnavailable('no_render_view');
            },
          );

      expect(
        response.errorCode,
        developer.ServiceExtensionResponse.extensionError,
      );
      expect(jsonDecode(response.errorDetail!), <String, dynamic>{
        'code': 1,
        'message': 'no_render_view',
      });
    },
  );
}
