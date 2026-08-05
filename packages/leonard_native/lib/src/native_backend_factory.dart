/// The single platform -> [NativeBackend] selection point.
///
/// The host runner (`bin/leonard_native_host.dart`) and any future embedder
/// pick a backend through here rather than constructing one directly, so
/// `--platform` wiring is testable without a VM service or a device.
library;

import 'xcuitest_backend.dart';
import 'native_backend.dart';
import 'uiautomator2_backend.dart';

/// Returns the [NativeBackend] for [platform] targeting [udid] + [app] on
/// [server] (default `http://127.0.0.1:4723`).
///
/// `ios` -> [XcuiTestBackend]; `android` -> [UiAutomator2Backend].
/// An unrecognized platform throws [ArgumentError] — LOUD, never a silent
/// fallback to iOS, which would perceive an Android target through an XCUITest
/// parser and yield an empty tree.
NativeBackend backendForPlatform({
  required String platform,
  required String udid,
  required String app,
  String? platformVersion,
  Uri? server,
}) => switch (platform) {
  'ios' => XcuiTestBackend(server: server, udid: udid, app: app),
  'android' => UiAutomator2Backend(
    server: server,
    udid: udid,
    app: app,
    platformVersion: platformVersion == null || platformVersion.isEmpty
        ? throw ArgumentError.value(
            platformVersion,
            'platformVersion',
            'Android requires --platform-version',
          )
        : platformVersion,
  ),
  _ => throw ArgumentError.value(
    platform,
    'platform',
    'unsupported native platform (expected "ios" or "android")',
  ),
};
