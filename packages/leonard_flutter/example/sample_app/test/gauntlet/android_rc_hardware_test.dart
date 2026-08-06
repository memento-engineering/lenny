@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

const String _serial = 'RF8RB21P6LN';
const String _package = 'com.example.sample_app';
const String _identifier = 'gauntlet_submit';
const String _route = '/g/control/label-lie';
final Uri _appium = Uri.parse('http://127.0.0.1:4723');

/// Probes the rig and SKIPS (never fails) when it is absent. This is a
/// hardware test: on a runner with no m22 attached and no Appium it must
/// step aside, not fail the suite — a hard failure here reads as a code
/// regression when it is only an environment fact (measured: PR #48's CI,
/// where this test was the sole red in 42). A skipped device test is NOT a
/// pass; the operator runs it against the real rig and quotes the
/// HARDWARE_ASSERT lines as the receipt.
Future<bool> _stationAvailable() async {
  final ProcessResult adb;
  try {
    adb = await Process.run('adb', <String>['-s', _serial, 'get-state']);
  } on ProcessException {
    return false; // no adb on PATH — not an Android rig
  }
  if (adb.exitCode != 0 || adb.stdout.toString().trim() != 'device') {
    return false; // the m22 is not attached
  }

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client.getUrl(
      _appium.resolve('/status'),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 500;
  } on Object {
    return false; // Appium not listening
  } finally {
    client.close(force: true);
  }
}

Future<Process> _launchGauntlet(List<String> logs) async {
  final Process process = await Process.start('flutter', <String>[
    'run',
    '--debug',
    '-d',
    _serial,
    '--route',
    _route,
  ]);
  final Completer<void> ready = Completer<void>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) {
      logs.add(line);
      if (line.contains('A Dart VM Service') && !ready.isCompleted) {
        ready.complete();
      }
    },
  );
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(logs.add);
  await ready.future.timeout(
    const Duration(minutes: 3),
    onTimeout: () => throw StateError(
      'sample app did not start on $_serial:\n${logs.join('\n')}',
    ),
  );
  return process;
}

Future<NativeSnapshot> _waitForIdentifier(UiAutomator2Backend backend) async {
  for (int attempt = 0; attempt < 20; attempt++) {
    final NativeSnapshot snapshot = await backend.snapshot();
    if (snapshot.nodes.any(
      (NativeNode node) => node.resourceId?.endsWith(_identifier) == true,
    )) {
      return snapshot;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('$_identifier absent from m22 /source');
}

void main() {
  test('0.3.0 Android RC seams execute on the m22 gauntlet', () async {
    if (!await _stationAvailable()) {
      markTestSkipped(
        'm22 ($_serial) not attached or Appium not at $_appium — '
        'hardware suite requires the real rig.',
      );
      return;
    }
    final List<String> logs = <String>[];
    final Process flutter = await _launchGauntlet(logs);
    final UiAutomator2Backend backend = UiAutomator2Backend(
      server: _appium,
      udid: _serial,
      app: _package,
    );
    try {
      await backend.connect(
        extraCapabilities: const <String, Object?>{
          'appium:disableIdLocatorAutocompletion': true,
          'appium:printPageSourceOnFindFailure': true,
        },
      );
      expect(backend.sessionProvenance?.deviceSerial, _serial);
      expect(
        backend.sessionCapabilities,
        containsPair('printPageSourceOnFindFailure', true),
      );
      stdout.writeln(
        'HARDWARE_ASSERT lenny-2d9z injected_capability '
        'appium:printPageSourceOnFindFailure=true '
        'returned=printPageSourceOnFindFailure:true serial=$_serial',
      );

      final NativeSnapshot snapshot = await _waitForIdentifier(backend);
      final NativeNode wrapper = snapshot.nodes.singleWhere(
        (NativeNode node) => node.resourceId?.endsWith(_identifier) == true,
      );
      final NativeTarget? resourceTarget = await backend.resolve(
        NativeSelector(resourceId: wrapper.resourceId),
        snapshot,
      );
      expect(resourceTarget, isNotNull);
      expect(resourceTarget!.via, 'resource-id');
      stdout.writeln(
        'HARDWARE_ASSERT lenny-bv7y resource_id_tier '
        'via=resource-id serial=$_serial',
      );

      final NativeTarget? semanticTarget = await backend.resolve(
        NativeSelector.flutterIdentifier(_identifier),
        snapshot,
      );
      expect(semanticTarget, isNotNull);
      expect(semanticTarget!.via, 'xpath');
      expect(semanticTarget.elementId, resourceTarget.elementId);
      await backend.tap(semanticTarget);
      stdout.writeln(
        'HARDWARE_ASSERT lenny-f0rq flutter_identifier '
        'projection=clickable-self via=xpath serial=$_serial',
      );
    } finally {
      await backend.close();
      flutter.stdin.writeln('q');
      await flutter.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          flutter.kill();
          return flutter.exitCode;
        },
      );
    }
  });
}
