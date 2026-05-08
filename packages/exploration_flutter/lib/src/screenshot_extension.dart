import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

class ScreenshotResult {
  ScreenshotResult({
    required this.pngBase64,
    required this.widthPx,
    required this.heightPx,
    required this.devicePixelRatio,
  });

  final String pngBase64;
  final int widthPx;
  final int heightPx;
  final double devicePixelRatio;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'png_base64': pngBase64,
        'width_px': widthPx,
        'height_px': heightPx,
        'device_pixel_ratio': devicePixelRatio,
      };
}

/// Mapped by the extension handler to JSON-RPC error code 1.
class ScreenshotUnavailable implements Exception {
  const ScreenshotUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'ScreenshotUnavailable: $reason';
}

Future<ScreenshotResult> captureScreenshot(RendererBinding binding) async {
  final Iterable<RenderView> views = binding.renderViews;
  if (views.isEmpty) {
    throw const ScreenshotUnavailable('no_render_view');
  }
  final RenderView view = views.first;
  final double dpr = view.flutterView.devicePixelRatio;
  // RenderView is a repaint boundary and owns an OffsetLayer
  // (TransformLayer extends OffsetLayer). Accessing `.layer` on a
  // foreign RenderObject is normally protected; we do it here from the
  // host binding which conceptually owns this RenderView.
  // ignore: invalid_use_of_protected_member
  final ContainerLayer? rootLayer = view.layer;
  if (rootLayer is! OffsetLayer) {
    throw const ScreenshotUnavailable('no_layer');
  }
  final ui.Image image =
      await rootLayer.toImage(view.paintBounds, pixelRatio: dpr);
  try {
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw const ScreenshotUnavailable('encode_failed');
    }
    final Uint8List png = bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    return ScreenshotResult(
      pngBase64: base64Encode(png),
      widthPx: image.width,
      heightPx: image.height,
      devicePixelRatio: dpr,
    );
  } finally {
    image.dispose();
  }
}
