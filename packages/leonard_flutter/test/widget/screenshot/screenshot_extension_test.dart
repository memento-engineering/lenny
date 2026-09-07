import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/src/screenshot_config.dart';
import 'package:leonard_flutter/src/screenshot_extension.dart';

const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=';

typedef _InspectorCall = ({String method, Map<String, dynamic> arguments});

class _FakeInspectorExtensionCaller {
  _FakeInspectorExtensionCaller({
    this.rootResult = const <String, dynamic>{'valueId': 'inspector-0'},
    this.screenshotResult = _onePixelPng,
    this.throwOnMethod,
    this.stallScreenshot = false,
  });

  final Object? rootResult;
  final Object? screenshotResult;
  final String? throwOnMethod;
  final bool stallScreenshot;
  final List<_InspectorCall> calls = <_InspectorCall>[];
  final Completer<Map<String, dynamic>> _stalledScreenshot =
      Completer<Map<String, dynamic>>();

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    calls.add((method: method, arguments: arguments));
    if (method == throwOnMethod) {
      throw StateError('Inspector call failed: $method');
    }
    return switch (method) {
      'ext.flutter.inspector.getRootWidget' => <String, dynamic>{
        'result': rootResult,
      },
      'ext.flutter.inspector.screenshot' when stallScreenshot =>
        _stalledScreenshot.future,
      'ext.flutter.inspector.screenshot' => <String, dynamic>{
        'result': screenshotResult,
      },
      'ext.flutter.inspector.disposeGroup' => <String, dynamic>{'result': null},
      _ => throw StateError('Unexpected inspector extension: $method'),
    };
  }
}

Matcher _isUnavailable(String reason) {
  return isA<ScreenshotUnavailable>().having(
    (ScreenshotUnavailable error) => error.reason,
    'reason',
    reason,
  );
}

void main() {
  testWidgets(
    'captureScreenshot delegates to the stock inspector screenshot extension',
    (WidgetTester tester) async {
      final _FakeInspectorExtensionCaller inspector =
          _FakeInspectorExtensionCaller();
      final view = tester.view;

      final ScreenshotResult result = await captureScreenshotFromInspector(
        view,
        inspector.call,
      );

      expect(inspector.calls, hasLength(3));
      expect(inspector.calls[0].method, 'ext.flutter.inspector.getRootWidget');
      expect(inspector.calls[0].arguments, <String, dynamic>{
        'objectGroup': ScreenshotConfig.inspectorObjectGroup,
      });
      expect(inspector.calls[1].method, 'ext.flutter.inspector.screenshot');
      expect(inspector.calls[1].arguments, <String, dynamic>{
        'id': 'inspector-0',
        'width': view.physicalSize.width.toString(),
        'height': view.physicalSize.height.toString(),
        'maxPixelRatio': view.devicePixelRatio.toString(),
        'margin': '0.0',
        'debugPaint': 'false',
      });
      expect(inspector.calls[2].method, 'ext.flutter.inspector.disposeGroup');
      expect(inspector.calls[2].arguments, <String, dynamic>{
        'objectGroup': ScreenshotConfig.inspectorObjectGroup,
      });
      expect(result.pngBase64, _onePixelPng);
      expect(result.widthPx, 1);
      expect(result.heightPx, 1);
      expect(result.devicePixelRatio, view.devicePixelRatio);
    },
  );

  testWidgets(
    'captureScreenshot times out a stalled inspector call within the capture budget',
    (WidgetTester tester) async {
      final _FakeInspectorExtensionCaller inspector =
          _FakeInspectorExtensionCaller(stallScreenshot: true);
      final Stopwatch stopwatch = Stopwatch()..start();

      await tester.runAsync<void>(() async {
        await expectLater(
          captureScreenshotFromInspector(
            tester.view,
            inspector.call,
            timeout: const Duration(milliseconds: 25),
          ),
          throwsA(_isUnavailable('inspector_unavailable')),
        );
      });
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(
        inspector.calls.map((_InspectorCall call) => call.method),
        <String>[
          'ext.flutter.inspector.getRootWidget',
          'ext.flutter.inspector.screenshot',
        ],
      );
    },
  );

  testWidgets('captureScreenshot preserves inspector failure reason mapping', (
    WidgetTester tester,
  ) async {
    final cases =
        <
          ({
            String label,
            Object? rootResult,
            Object? screenshotResult,
            String? throwOnMethod,
            String reason,
          })
        >[
          (
            label: 'missing root id',
            rootResult: const <String, dynamic>{},
            screenshotResult: _onePixelPng,
            throwOnMethod: null,
            reason: 'no_render_view',
          ),
          (
            label: 'null screenshot',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: null,
            throwOnMethod: null,
            reason: 'no_layer',
          ),
          (
            label: 'empty screenshot',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: '',
            throwOnMethod: null,
            reason: 'no_layer',
          ),
          (
            label: 'malformed base64',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: '%',
            throwOnMethod: null,
            reason: 'encode_failed',
          ),
          (
            label: 'malformed PNG',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: 'bm90IGEgcG5n',
            throwOnMethod: null,
            reason: 'encode_failed',
          ),
          (
            label: 'non-string screenshot',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: 42,
            throwOnMethod: null,
            reason: 'encode_failed',
          ),
          (
            label: 'caller failure',
            rootResult: const <String, dynamic>{'valueId': 'inspector-0'},
            screenshotResult: _onePixelPng,
            throwOnMethod: 'ext.flutter.inspector.screenshot',
            reason: 'inspector_unavailable',
          ),
        ];

    for (final testCase in cases) {
      final _FakeInspectorExtensionCaller inspector =
          _FakeInspectorExtensionCaller(
            rootResult: testCase.rootResult,
            screenshotResult: testCase.screenshotResult,
            throwOnMethod: testCase.throwOnMethod,
          );

      await expectLater(
        captureScreenshotFromInspector(tester.view, inspector.call),
        throwsA(_isUnavailable(testCase.reason)),
        reason: testCase.label,
      );
      expect(
        inspector.calls.last.method,
        'ext.flutter.inspector.disposeGroup',
        reason: testCase.label,
      );
    }
  });

  test('ScreenshotUnavailable carries reason', () {
    expect(
      const ScreenshotUnavailable('no_render_view').reason,
      'no_render_view',
    );
  });
}
