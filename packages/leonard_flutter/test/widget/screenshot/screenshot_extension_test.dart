import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/src/screenshot_extension.dart';

const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=';

class _FakeInspectorScreenshot {
  _FakeInspectorScreenshot({this.image, this.error, this.stall = false});

  final ui.Image? image;
  final Object? error;
  final bool stall;

  int calls = 0;
  Object? object;
  double? width;
  double? height;
  double? margin;
  double? maxPixelRatio;
  bool? debugPaint;

  Future<ui.Image?> call(
    Object? object, {
    required double width,
    required double height,
    double margin = 0,
    double maxPixelRatio = 1,
    bool debugPaint = false,
  }) async {
    calls += 1;
    this.object = object;
    this.width = width;
    this.height = height;
    this.margin = margin;
    this.maxPixelRatio = maxPixelRatio;
    this.debugPaint = debugPaint;
    final Object? captureError = error;
    if (captureError != null) {
      throw captureError;
    }
    if (stall) {
      return Completer<ui.Image?>().future;
    }
    return image;
  }
}

Matcher _isUnavailable(String reason) {
  return isA<ScreenshotUnavailable>().having(
    (ScreenshotUnavailable error) => error.reason,
    'reason',
    reason,
  );
}

Future<ui.Image> _createOnePixelImage() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final ui.Picture picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}

ByteData _paddedPngByteData() {
  final Uint8List png = base64Decode(_onePixelPng);
  final Uint8List storage = Uint8List(png.length + 7)
    ..setRange(3, 3 + png.length, png);
  return ByteData.view(storage.buffer, 3, png.length);
}

ByteData _zeroDimensionPngByteData() {
  final Uint8List png = Uint8List(24)
    ..setAll(0, const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..setAll(8, const <int>[0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  return ByteData.sublistView(png);
}

Future<ui.Image?> _unexpectedCapture(
  Object? object, {
  required double width,
  required double height,
  double margin = 0,
  double maxPixelRatio = 1,
  bool debugPaint = false,
}) {
  throw StateError('Inspector capture should not have been called');
}

void main() {
  testWidgets('captureScreenshot uses WidgetInspectorService in process', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 20,
          height: 10,
          child: ColoredBox(color: Color(0xFFFF0000)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ScreenshotResult? result = await tester.runAsync(captureScreenshot);

    expect(result, isNotNull);
    expect(result!.pngBase64, isNotEmpty);
    expect(result.widthPx, greaterThan(0));
    expect(result.heightPx, greaterThan(0));
  });

  testWidgets(
    'captureScreenshotFromInspector preserves pixels and view metadata',
    (WidgetTester tester) async {
      final ui.Image image = await _createOnePixelImage();
      final _FakeInspectorScreenshot inspector = _FakeInspectorScreenshot(
        image: image,
      );
      final Object rootElement = Object();
      ui.Image? imagePassedToEncoder;

      final ScreenshotResult result = await captureScreenshotFromInspector(
        views: <ui.FlutterView>[tester.view],
        rootElement: rootElement,
        capture: inspector.call,
        encodePng: (ui.Image candidate) async {
          imagePassedToEncoder = candidate;
          return _paddedPngByteData();
        },
      );

      expect(inspector.calls, 1);
      expect(inspector.object, same(rootElement));
      expect(inspector.width, tester.view.physicalSize.width);
      expect(inspector.height, tester.view.physicalSize.height);
      expect(inspector.margin, 0);
      expect(inspector.maxPixelRatio, tester.view.devicePixelRatio);
      expect(inspector.debugPaint, isFalse);
      expect(imagePassedToEncoder, same(image));
      expect(base64Decode(result.pngBase64).sublist(0, 8), const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      expect(result.pngBase64, _onePixelPng);
      expect(result.widthPx, 1);
      expect(result.heightPx, 1);
      expect(result.devicePixelRatio, tester.view.devicePixelRatio);
      expect(image.debugDisposed, isTrue);
    },
  );

  testWidgets('captureScreenshotFromInspector reports distinct failure codes', (
    WidgetTester tester,
  ) async {
    final List<
      ({
        String label,
        String reason,
        Duration? maximumElapsed,
        Future<ScreenshotResult> Function() run,
      })
    >
    cases =
        <
          ({
            String label,
            String reason,
            Duration? maximumElapsed,
            Future<ScreenshotResult> Function() run,
          })
        >[
          (
            label: 'no view',
            reason: 'no_render_view',
            maximumElapsed: null,
            run: () => captureScreenshotFromInspector(
              views: const <ui.FlutterView>[],
              rootElement: Object(),
              capture: _unexpectedCapture,
            ),
          ),
          (
            label: 'no root widget',
            reason: 'no_root_widget',
            maximumElapsed: null,
            run: () => captureScreenshotFromInspector(
              views: <ui.FlutterView>[tester.view],
              rootElement: null,
              capture: _unexpectedCapture,
            ),
          ),
          (
            label: 'no inspector image',
            reason: 'no_layer',
            maximumElapsed: null,
            run: () => captureScreenshotFromInspector(
              views: <ui.FlutterView>[tester.view],
              rootElement: Object(),
              capture: _FakeInspectorScreenshot().call,
            ),
          ),
          (
            label: 'capture timeout',
            reason: 'capture_timeout',
            maximumElapsed: const Duration(seconds: 1),
            run: () => captureScreenshotFromInspector(
              views: <ui.FlutterView>[tester.view],
              rootElement: Object(),
              capture: _FakeInspectorScreenshot(stall: true).call,
              timeout: const Duration(milliseconds: 25),
            ),
          ),
          (
            label: 'inspector exception',
            reason: 'capture_failed',
            maximumElapsed: null,
            run: () => captureScreenshotFromInspector(
              views: <ui.FlutterView>[tester.view],
              rootElement: Object(),
              capture: _FakeInspectorScreenshot(
                error: StateError('capture failed'),
              ).call,
            ),
          ),
          (
            label: 'null PNG bytes',
            reason: 'encode_failed',
            maximumElapsed: null,
            run: () async {
              final ui.Image image = await _createOnePixelImage();
              return captureScreenshotFromInspector(
                views: <ui.FlutterView>[tester.view],
                rootElement: Object(),
                capture: _FakeInspectorScreenshot(image: image).call,
                encodePng: (ui.Image image) async => null,
              );
            },
          ),
          (
            label: 'PNG encoder exception',
            reason: 'encode_failed',
            maximumElapsed: null,
            run: () async {
              final ui.Image image = await _createOnePixelImage();
              return captureScreenshotFromInspector(
                views: <ui.FlutterView>[tester.view],
                rootElement: Object(),
                capture: _FakeInspectorScreenshot(image: image).call,
                encodePng: (ui.Image image) async {
                  throw StateError('encode failed');
                },
              );
            },
          ),
          (
            label: 'malformed PNG',
            reason: 'encode_failed',
            maximumElapsed: null,
            run: () async {
              final ui.Image image = await _createOnePixelImage();
              return captureScreenshotFromInspector(
                views: <ui.FlutterView>[tester.view],
                rootElement: Object(),
                capture: _FakeInspectorScreenshot(image: image).call,
                encodePng: (ui.Image image) async => ByteData.sublistView(
                  Uint8List.fromList(const <int>[1, 2, 3]),
                ),
              );
            },
          ),
          (
            label: 'zero PNG dimensions',
            reason: 'encode_failed',
            maximumElapsed: null,
            run: () async {
              final ui.Image image = await _createOnePixelImage();
              return captureScreenshotFromInspector(
                views: <ui.FlutterView>[tester.view],
                rootElement: Object(),
                capture: _FakeInspectorScreenshot(image: image).call,
                encodePng: (ui.Image image) async =>
                    _zeroDimensionPngByteData(),
              );
            },
          ),
        ];
    final Set<String> observedReasons = <String>{};

    await tester.runAsync<void>(() async {
      for (final testCase in cases) {
        final Stopwatch stopwatch = Stopwatch()..start();
        await expectLater(
          testCase.run(),
          throwsA(_isUnavailable(testCase.reason)),
          reason: testCase.label,
        );
        stopwatch.stop();
        observedReasons.add(testCase.reason);
        final Duration? maximumElapsed = testCase.maximumElapsed;
        if (maximumElapsed != null) {
          expect(
            stopwatch.elapsed,
            lessThan(maximumElapsed),
            reason: testCase.label,
          );
        }
      }
    });

    expect(observedReasons, <String>{
      'no_render_view',
      'no_root_widget',
      'no_layer',
      'capture_timeout',
      'capture_failed',
      'encode_failed',
    });
  });

  test('ScreenshotUnavailable carries reason', () {
    expect(
      const ScreenshotUnavailable('no_render_view').reason,
      'no_render_view',
    );
  });
}
