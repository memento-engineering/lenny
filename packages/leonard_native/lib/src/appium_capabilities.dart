/// Appium capability names that define whether a session attaches, installs,
/// resets, or launches the application under test.
const Set<String> appiumAttachCriticalCapabilityKeys = <String>{
  'appium:app',
  'appium:bundleId',
  'appium:appPackage',
  'appium:appActivity',
  'appium:autoLaunch',
  'appium:noReset',
  'appium:fullReset',
  'appium:skipAppKill',
  'appium:appPath',
  'app',
  'bundleId',
  'appPackage',
  'appActivity',
  'autoLaunch',
  'noReset',
  'fullReset',
  'skipAppKill',
  'appPath',
};

/// Builds the immutable capabilities for attaching Mac2 to [bundleId].
///
/// The application and Appium server must already be running. These defaults
/// make the session own neither application launch nor application teardown;
/// attach-critical [extraCapabilities] are rejected by
/// [mergeAppiumCapabilities].
Map<String, Object?> mac2AttachCapabilities({
  required String bundleId,
  Map<String, Object?> extraCapabilities = const <String, Object?>{},
}) {
  if (bundleId.trim().isEmpty) {
    throw ArgumentError.value(
      bundleId,
      'bundleId',
      'Mac2 attach requires a non-empty bundleId',
    );
  }
  return Map<String, Object?>.unmodifiable(
    mergeAppiumCapabilities(
      defaults: <String, Object?>{
        'platformName': 'mac',
        'appium:automationName': 'Mac2',
        'appium:bundleId': bundleId,
        'appium:noReset': true,
        'appium:skipAppKill': true,
      },
      extraCapabilities: extraCapabilities,
    ),
  );
}

/// Merges orthogonal [extraCapabilities] over [defaults].
///
/// Attach-critical capabilities are refused rather than silently changing the
/// process lifecycle that the backend owns.
Map<String, Object?> mergeAppiumCapabilities({
  required Map<String, Object?> defaults,
  required Map<String, Object?> extraCapabilities,
}) {
  final List<String> denied =
      extraCapabilities.keys
          .where(appiumAttachCriticalCapabilityKeys.contains)
          .toList()
        ..sort();
  if (denied.isNotEmpty) {
    throw ArgumentError(
      'attach-critical Appium capabilities cannot be overridden: '
          '${denied.join(', ')}',
      'extraCapabilities',
    );
  }
  return <String, Object?>{...defaults, ...extraCapabilities};
}
