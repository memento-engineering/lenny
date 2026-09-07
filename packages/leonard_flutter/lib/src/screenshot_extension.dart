import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:vm_service/vm_service.dart' show Response, VmService;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

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

/// Calls an inspector service extension with string-valued protocol arguments.
typedef InspectorExtensionCaller =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> args,
    );

/// Captures the first Flutter view through the stock inspector extension.
Future<ScreenshotResult> captureScreenshot() async {
  final Iterable<FlutterView> views = PlatformDispatcher.instance.views;
  if (views.isEmpty) {
    throw const ScreenshotUnavailable('no_render_view');
  }
  final FlutterView view = views.first;

  VmService? connection;
  Future<VmService>? pendingConnection;
  var captureEnded = false;
  try {
    final Uri? webSocketUri =
        (await developer.Service.getInfo()).serverWebSocketUri;
    final String? isolateId = developer.Service.getIsolateId(Isolate.current);
    if (webSocketUri == null || isolateId == null) {
      throw const ScreenshotUnavailable('inspector_unavailable');
    }

    Future<Map<String, dynamic>> callInspectorExtension(
      String method,
      Map<String, dynamic> args,
    ) async {
      final VmService service = await (pendingConnection ??= vm_service_io
          .vmServiceConnectUri(webSocketUri.toString()));
      if (captureEnded) {
        try {
          await service.dispose();
        } catch (_) {
          // The capture has already completed with a stable result or reason.
        }
        throw StateError('Screenshot capture ended before VM connection');
      }
      connection = service;
      final Response response = await service.callServiceExtension(
        method,
        isolateId: isolateId,
        args: args,
      );
      return response.json ?? <String, dynamic>{};
    }

    return await captureScreenshotFromInspector(view, callInspectorExtension);
  } on ScreenshotUnavailable {
    rethrow;
  } catch (_) {
    throw const ScreenshotUnavailable('inspector_unavailable');
  } finally {
    captureEnded = true;
    try {
      await connection?.dispose();
    } catch (_) {
      // Capture already has a result or a stable failure reason.
    }
  }
}

/// Captures [view] by delegating root lookup and PNG production to [caller].
///
/// This public seam keeps inspector protocol behavior testable without opening
/// a VM-service connection.
Future<ScreenshotResult> captureScreenshotFromInspector(
  FlutterView view,
  InspectorExtensionCaller caller, {
  Duration timeout = ScreenshotConfig.inspectorCaptureTimeout,
}) async {
  try {
    return await _captureScreenshotFromInspector(view, caller).timeout(timeout);
  } on ScreenshotUnavailable {
    rethrow;
  } catch (_) {
    throw const ScreenshotUnavailable('inspector_unavailable');
  }
}

Future<ScreenshotResult> _captureScreenshotFromInspector(
  FlutterView view,
  InspectorExtensionCaller caller,
) async {
  const String group = ScreenshotConfig.inspectorObjectGroup;
  ScreenshotUnavailable? stableFailure;
  try {
    final Map<String, dynamic> rootResponse = await caller(
      'ext.flutter.inspector.getRootWidget',
      const <String, dynamic>{'objectGroup': group},
    );
    final Object? root = rootResponse['result'];
    final Object? rootId = root is Map ? root['valueId'] : null;
    if (rootId is! String || rootId.isEmpty) {
      throw const ScreenshotUnavailable('no_render_view');
    }

    final Map<String, dynamic> screenshotResponse = await caller(
      'ext.flutter.inspector.screenshot',
      ScreenshotConfig.inspectorScreenshotArguments(view, rootId),
    );
    final Object? encoded = screenshotResponse['result'];
    if (encoded == null || encoded is String && encoded.isEmpty) {
      throw const ScreenshotUnavailable('no_layer');
    }
    if (encoded is! String) {
      throw const ScreenshotUnavailable('encode_failed');
    }

    final ({int width, int height}) dimensions = _decodePngDimensions(encoded);
    return ScreenshotResult(
      pngBase64: encoded,
      widthPx: dimensions.width,
      heightPx: dimensions.height,
      devicePixelRatio: view.devicePixelRatio,
    );
  } on ScreenshotUnavailable catch (error) {
    stableFailure = error;
    rethrow;
  } finally {
    try {
      await caller(
        'ext.flutter.inspector.disposeGroup',
        const <String, dynamic>{'objectGroup': group},
      );
    } catch (_) {
      if (stableFailure == null) {
        rethrow;
      }
    }
  }
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
