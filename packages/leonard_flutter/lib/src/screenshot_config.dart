import 'dart:ui' show FlutterView;

/// Default-enabled flags for `ext.leonard.core.screenshot`,
/// keyed by model capability. Read by the harness per turn.
class ScreenshotConfig {
  /// Default ON for vision-capable models (PRD §11.1, §16.3).
  static const bool defaultEnabledForVisionModel = true;

  /// Default OFF for text-only models (PRD §11.1).
  static const bool defaultEnabledForTextModel = false;

  /// Total budget for root lookup, screenshot capture, and group disposal.
  static const Duration inspectorCaptureTimeout = Duration(seconds: 3);

  /// Inspector object group used for each screenshot capture.
  static const String inspectorObjectGroup = 'leonard-screenshot';

  /// Builds the stock inspector screenshot arguments for the complete [view].
  static Map<String, dynamic> inspectorScreenshotArguments(
    FlutterView view,
    String rootId,
  ) {
    return <String, dynamic>{
      'id': rootId,
      'width': view.physicalSize.width.toString(),
      'height': view.physicalSize.height.toString(),
      'maxPixelRatio': view.devicePixelRatio.toString(),
      'margin': '0.0',
      'debugPaint': 'false',
    };
  }

  const ScreenshotConfig._();
}
