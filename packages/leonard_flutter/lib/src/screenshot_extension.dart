import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/widgets.dart'
    show WidgetInspectorService, WidgetsBinding;

import 'screenshot_config.dart';

/// A PNG screenshot and the view metadata exposed on Leonard's wire protocol.
class ScreenshotResult {
  /// Creates a screenshot result.
  ScreenshotResult({
    required this.pngBase64,
    required this.widthPx,
    required this.heightPx,
    required this.devicePixelRatio,
  });

  /// Base64-encoded PNG bytes.
  final String pngBase64;

  /// Width encoded in the PNG's `IHDR` chunk.
  final int widthPx;

  /// Height encoded in the PNG's `IHDR` chunk.
  final int heightPx;

  /// Device-pixel ratio of the captured Flutter view.
  final double devicePixelRatio;

  /// Encodes the stable Leonard screenshot wire shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'png_base64': pngBase64,
    'width_px': widthPx,
    'height_px': heightPx,
    'device_pixel_ratio': devicePixelRatio,
  };
}

/// Mapped by the extension handler to JSON-RPC error code 1.
class ScreenshotUnavailable implements Exception {
  /// Creates an unavailable error with a stable wire [reason].
  const ScreenshotUnavailable(this.reason);

  /// Stable reason sent to Leonard clients.
  final String reason;

  @override
  String toString() => 'ScreenshotUnavailable: $reason';
}

/// Captures one screenshot for Leonard's service-extension response.
typedef ScreenshotCapture = Future<ScreenshotResult> Function();

/// Captures an inspector image for [object] within the requested pixel bounds.
typedef InspectorScreenshotCapture =
    Future<ui.Image?> Function(
      Object? object, {
      required double width,
      required double height,
      double margin,
      double maxPixelRatio,
      bool debugPaint,
    });

/// Encodes an inspector [ui.Image] as PNG bytes.
typedef ScreenshotPngEncoder = Future<ByteData?> Function(ui.Image image);

/// Captures the first Flutter view through the stock inspector implementation.
Future<ScreenshotResult> captureScreenshot() {
  return captureScreenshotFromInspector(
    views: PlatformDispatcher.instance.views,
    rootElement: WidgetsBinding.instance.rootElement,
    // This deliberately reuses the stock inspector's screenshot implementation.
    // ignore: invalid_use_of_protected_member
    capture: WidgetInspectorService.instance.screenshot,
    encodePng: _encodePng,
  );
}

/// Captures the first of [views] from [rootElement] using [capture].
///
/// Inspector image creation and [encodePng] share the single [timeout] budget.
Future<ScreenshotResult> captureScreenshotFromInspector({
  required Iterable<FlutterView> views,
  required Object? rootElement,
  required InspectorScreenshotCapture capture,
  ScreenshotPngEncoder encodePng = _encodePng,
  Duration timeout = ScreenshotConfig.inspectorCaptureTimeout,
}) async {
  final Iterator<FlutterView> iterator = views.iterator;
  if (!iterator.moveNext()) {
    throw const ScreenshotUnavailable('no_render_view');
  }
  if (rootElement == null) {
    throw const ScreenshotUnavailable('no_root_widget');
  }

  return await _captureScreenshotFromInspector(
    view: iterator.current,
    rootElement: rootElement,
    capture: capture,
    encodePng: encodePng,
  ).timeout(
    timeout,
    onTimeout: () => throw const ScreenshotUnavailable('capture_timeout'),
  );
}

Future<ScreenshotResult> _captureScreenshotFromInspector({
  required FlutterView view,
  required Object rootElement,
  required InspectorScreenshotCapture capture,
  required ScreenshotPngEncoder encodePng,
}) async {
  ui.Image? image;
  try {
    image = await capture(
      rootElement,
      width: view.physicalSize.width,
      height: view.physicalSize.height,
      margin: 0,
      maxPixelRatio: view.devicePixelRatio,
      debugPaint: false,
    );
  } on ScreenshotUnavailable {
    rethrow;
  } on Object {
    throw const ScreenshotUnavailable('capture_failed');
  }

  if (image == null) {
    throw const ScreenshotUnavailable('no_layer');
  }

  try {
    final ByteData? encodedBytes;
    try {
      encodedBytes = await encodePng(image);
    } on Object {
      throw const ScreenshotUnavailable('encode_failed');
    }
    if (encodedBytes == null) {
      throw const ScreenshotUnavailable('encode_failed');
    }

    final Uint8List png = encodedBytes.buffer.asUint8List(
      encodedBytes.offsetInBytes,
      encodedBytes.lengthInBytes,
    );
    final String encoded = base64Encode(png);
    final ({int width, int height}) dimensions = _decodePngDimensions(encoded);
    return ScreenshotResult(
      pngBase64: encoded,
      widthPx: dimensions.width,
      heightPx: dimensions.height,
      devicePixelRatio: view.devicePixelRatio,
    );
  } finally {
    image.dispose();
  }
}

Future<ByteData?> _encodePng(ui.Image image) {
  return image.toByteData(format: ui.ImageByteFormat.png);
}

/// Builds the response for `ext.leonard.core.screenshot`.
Future<developer.ServiceExtensionResponse> screenshotServiceExtensionResponse({
  ScreenshotCapture capture = captureScreenshot,
}) async {
  try {
    final ScreenshotResult result = await capture();
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{'result': result.toJson()}),
    );
  } on ScreenshotUnavailable catch (error) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      jsonEncode(<String, dynamic>{'code': 1, 'message': error.reason}),
    );
  }
}

({int width, int height}) _decodePngDimensions(String encoded) {
  try {
    final Uint8List png = base64Decode(encoded);
    const List<int> signature = <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ];
    if (png.length < 24 ||
        !_matches(png, 0, signature) ||
        _readBigEndianUint32(png, 8) != 13 ||
        !_matches(png, 12, const <int>[0x49, 0x48, 0x44, 0x52])) {
      throw const ScreenshotUnavailable('encode_failed');
    }
    final int width = _readBigEndianUint32(png, 16);
    final int height = _readBigEndianUint32(png, 20);
    if (width == 0 || height == 0) {
      throw const ScreenshotUnavailable('encode_failed');
    }
    return (width: width, height: height);
  } on ScreenshotUnavailable {
    rethrow;
  } on FormatException {
    throw const ScreenshotUnavailable('encode_failed');
  } on RangeError {
    throw const ScreenshotUnavailable('encode_failed');
  }
}

bool _matches(Uint8List bytes, int offset, List<int> expected) {
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) {
      return false;
    }
  }
  return true;
}

int _readBigEndianUint32(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getUint32(offset);
}
