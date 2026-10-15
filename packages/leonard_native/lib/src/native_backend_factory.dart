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
/// Mobile platforms require a non-empty [udid] and exactly one lifecycle:
/// [app] installs and launches it ([NativeLaunch]); [appId] attaches to that
/// already-running app ([NativeAttach]). `darwin` requires a non-empty [appId]
/// (the bundle id) and attaches [Mac2Backend] to that running app.
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
  String? appId,
  String? platformVersion,
  Uri? server,
}) {
  if (platform == 'darwin') {
    return Mac2Backend(
      server: server,
      bundleId: _requiredTarget(appId, 'appId', platform),
    );
  }
  final (NativeLaunch launch, NativeAttach attach) = switch (platform) {
    'ios' => (XcuiTestBackend.new, XcuiTestBackend.attach),
    'android' => (UiAutomator2Backend.new, UiAutomator2Backend.attach),
    _ => throw ArgumentError.value(
      platform,
      'platform',
      'unsupported native platform '
          '(expected "ios", "android", or "darwin")',
    ),
  };
  final String device = _requiredTarget(udid, 'udid', platform);
  return switch ((_nonEmpty(app), _nonEmpty(appId))) {
    (final String app, null) => launch(
      server: server,
      udid: device,
      app: app,
      platformVersion: platformVersion,
    ),
    (null, final String appId) => attach(
      server: server,
      udid: device,
      appId: appId,
      platformVersion: platformVersion,
    ),
    (null, null) => throw ArgumentError.value(
      app,
      'app',
      '$platform requires app (install and launch) or appId (attach to the '
          'running app)',
    ),
    (_, _) => throw ArgumentError.value(
      appId,
      'appId',
      '$platform takes app (install and launch) or appId (attach), not both',
    ),
  };
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

String _requiredTarget(String? value, String name, String platform) =>
    _nonEmpty(value) ??
    (throw ArgumentError.value(
      value,
      name,
      '$platform requires a non-empty $name',
    ));
