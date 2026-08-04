/// Appium capability names that define whether a session attaches, installs,
/// resets, or launches the application under test.
const Set<String> appiumAttachCriticalCapabilityKeys = <String>{
  'appium:app',
  'appium:appPackage',
  'appium:appActivity',
  'appium:autoLaunch',
  'appium:noReset',
  'appium:fullReset',
  'app',
  'appPackage',
  'appActivity',
  'autoLaunch',
  'noReset',
  'fullReset',
};

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
