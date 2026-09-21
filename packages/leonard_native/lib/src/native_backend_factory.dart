/// The single platform -> [NativeBackend] selection point.
///
/// The host runner (`bin/leonard_native_host.dart`) and any future embedder
/// pick a backend through here rather than constructing one directly, so
/// `--platform` wiring is testable without a VM service or a device.
library;

import 'mac2_backend.dart';
import 'xcuitest_backend.dart';
import 'native_backend.dart';
import 'uiautomator2_backend.dart';

/// Returns the [NativeBackend] for [platform] on [server] (default
/// `http://127.0.0.1:4723`).
///
/// Mobile platforms require non-empty [udid] and [app]. `darwin` requires a
/// non-empty [bundleId] and attaches [Mac2Backend] to that running app.
///
/// `ios` -> [XcuiTestBackend]; `android` -> [UiAutomator2Backend]; `darwin` ->
/// [Mac2Backend].
/// An unrecognized platform throws [ArgumentError] — LOUD, never a silent
/// fallback to iOS, which would perceive an Android target through an XCUITest
/// parser and yield an empty tree.
NativeBackend backendForPlatform({
  required String platform,
  String? udid,
  String? app,
  String? bundleId,
  String? platformVersion,
  Uri? server,
}) {
  switch (platform) {
    case 'ios':
      return XcuiTestBackend(
        server: server,
        udid: _requiredTarget(udid, 'udid', platform),
        app: _requiredTarget(app, 'app', platform),
      );
    case 'android':
      return UiAutomator2Backend(
        server: server,
        udid: _requiredTarget(udid, 'udid', platform),
        app: _requiredTarget(app, 'app', platform),
        platformVersion: platformVersion,
      );
    case 'darwin':
      return Mac2Backend(
        server: server,
        bundleId: _requiredTarget(bundleId, 'bundleId', platform),
      );
    default:
      throw ArgumentError.value(
        platform,
        'platform',
        'unsupported native platform '
            '(expected "ios", "android", or "darwin")',
      );
  }
}

String _requiredTarget(String? value, String name, String platform) {
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError.value(
      value,
      name,
      '$platform requires a non-empty $name',
    );
  }
  return value;
}
