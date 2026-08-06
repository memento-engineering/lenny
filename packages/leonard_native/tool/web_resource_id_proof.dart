/// Live device proof for GitHub #51 / lenny-caaj: a BARE HTML id inside
/// Chrome web content resolves through the patched resource-id tier's xpath
/// fallback, and a `pkg:id/name` native id still resolves through `using=id`.
///
/// Drives the attached device's real Chrome at a page with known bare ids
/// (the-internet.herokuapp.com/login: `username`, `password`). Requires an
/// already-running Appium server and the wired device; prints
/// `HARDWARE_ASSERT` lines on success and exits non-zero on any failure.
library;

import 'dart:io';

import 'package:leonard_native/leonard_native.dart';

const String serial = 'RF8RB21P6LN';
const String page = 'https://the-internet.herokuapp.com/login';

Future<void> main() async {
  final UiAutomator2Backend backend = UiAutomator2Backend(
    server: Uri.parse('http://127.0.0.1:4723'),
    udid: serial,
    app: 'com.android.chrome',
  );
  await backend.connect();
  try {
    // Navigate the REAL Chrome to the page via an explicit VIEW intent.
    final ProcessResult nav = await Process.run('adb', <String>[
      '-s',
      serial,
      'shell',
      'am',
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      page,
      'com.android.chrome',
    ]);
    if (nav.exitCode != 0) {
      throw StateError('chrome navigation failed: ${nav.stderr}');
    }
    await Future<void>.delayed(const Duration(seconds: 6));

    // 1) The #51 defect shape: a bare web-content id. Pre-patch this missed
    //    outright after the full using=id retry window.
    final NativeTarget? web = await backend.resolve(
      const NativeSelector(resourceId: 'username'),
      null,
    );
    if (web == null) {
      throw StateError('bare id "username" did not resolve');
    }
    if (web.via != 'resource-id-xpath') {
      throw StateError('expected via=resource-id-xpath, got ${web.via}');
    }
    stdout.writeln(
      'HARDWARE_ASSERT lenny-caaj web_resource_id id=username '
      'via=${web.via} serial=$serial page=$page',
    );

    // 2) The unchanged native path: a real view resource name resolves
    //    through using=id with no fallback involved.
    final NativeTarget? native = await backend.resolve(
      const NativeSelector(resourceId: 'android:id/content'),
      null,
    );
    if (native == null) {
      throw StateError('native id android:id/content did not resolve');
    }
    if (native.via != 'resource-id') {
      throw StateError('expected via=resource-id, got ${native.via}');
    }
    stdout.writeln(
      'HARDWARE_ASSERT lenny-caaj native_resource_id id=android:id/content '
      'via=${native.via} serial=$serial',
    );
    stdout.writeln('HARDWARE_PROOF PASS serial=$serial');
  } finally {
    await backend.close();
  }
}
