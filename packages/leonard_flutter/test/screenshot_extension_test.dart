import 'dart:convert';
import 'dart:typed_data';

import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captureScreenshot returns valid PNG with correct dims',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 200,
        height: 100,
        child: ColoredBox(color: Color(0xFFFF0000)),
      ),
    ));
    await tester.pumpAndSettle();

    final ScreenshotResult result = (await tester.runAsync<ScreenshotResult>(
        () => captureScreenshot(tester.binding)))!;

    expect(result.pngBase64, isNotEmpty);
    expect(result.widthPx, greaterThan(0));
    expect(result.heightPx, greaterThan(0));

    final Uint8List bytes = base64Decode(result.pngBase64);
    expect(bytes.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    int beU32(int o) => (bytes[o] << 24) |
        (bytes[o + 1] << 16) |
        (bytes[o + 2] << 8) |
        bytes[o + 3];
    expect(beU32(16), result.widthPx);
    expect(beU32(20), result.heightPx);
  });

  test('ScreenshotUnavailable carries reason', () {
    expect(const ScreenshotUnavailable('no_render_view').reason,
        'no_render_view');
  });
}
