/// Default-enabled flags for `ext.exploration.core.screenshot`,
/// keyed by model capability. Read by the harness (cx6.14) per turn.
class ScreenshotConfig {
  /// Default ON for vision-capable models (PRD §11.1, §16.3).
  static const bool defaultEnabledForVisionModel = true;

  /// Default OFF for text-only models (PRD §11.1).
  static const bool defaultEnabledForTextModel = false;

  const ScreenshotConfig._();
}
