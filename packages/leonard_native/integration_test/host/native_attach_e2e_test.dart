/// Live, wired iOS-device attach proof. RUNBOOK §0 requires the device to be
/// wired; §6 requires stale iproxy processes to be terminated before running.
library;

import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

const String _udidEnv = 'LEONARD_NATIVE_IOS_DEVICE_UDID';
const String _bundleEnv = 'LEONARD_NATIVE_IOS_BUNDLE_ID';
const String _serverEnv = 'LEONARD_NATIVE_APPIUM_SERVER';

void main() {
  final String? udid = Platform.environment[_udidEnv];
  final String? bundleId = Platform.environment[_bundleEnv];

  test('attaches to a live iOS app by bundle id without appium:app', () async {
    if (udid == null || udid.isEmpty || bundleId == null || bundleId.isEmpty) {
      markTestSkipped(
        '$_udidEnv + $_bundleEnv are required — live iOS attach e2e skipped',
      );
      return;
    }
    final XcuiTestBackend backend = XcuiTestBackend.attach(
      server: Uri.parse(
        Platform.environment[_serverEnv] ?? 'http://127.0.0.1:4723',
      ),
      udid: udid,
      bundleId: bundleId,
    );
    await backend.connect(
      extraCapabilities: const <String, Object?>{
        'appium:wdaLaunchTimeout': 240000,
      },
    );
    try {
      final NativeSnapshot snapshot = await backend.snapshot();
      expect(snapshot.platform, 'ios');
      expect(snapshot.nodes, isNotEmpty);
      expect(backend.app, isNull);
      expect(backend.bundleId, bundleId);
      stdout.writeln(
        'HARDWARE_ASSERT lenny-sx8c attach_bundle_id udid=$udid '
        'bundle=$bundleId appium_app=absent',
      );
      stdout.writeln(
        'HARDWARE_ASSERT lenny-2d9z ios_injected_capability udid=$udid',
      );
    } finally {
      await backend.close();
    }
  });
}
