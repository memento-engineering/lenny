@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../integration_test/support/device_e2e_up.dart';

void main() {
  final String packageRoot = _findPackageRoot();
  final String fixture = p.join(
    packageRoot,
    'test',
    'support',
    'device_e2e_up_fixture.dart',
  );

  test(
    'thrown assertion reaps the up parent and both children before returning',
    () async {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'device_e2e_up_throw',
      );
      final List<int> ports = await _unusedPorts();
      final String pidFile = p.join(tmp.path, 'up.pid');
      final DeviceE2eUp up = await _startFixture(
        fixture: fixture,
        packageRoot: packageRoot,
        pidFile: pidFile,
        ports: ports,
      );
      Object? assertion;
      try {
        try {
          await (() async {
            try {
              final Map<String, dynamic> envelope = await _waitForReady(up);
              expect(envelope['pid'], isA<int>());
              expect(await _canBindBoth(ports), isFalse);
              expect(false, isTrue, reason: 'deliberately thrown assertion');
            } finally {
              await up.stop();
              expect(await up.exitCode, 0);
              expect(await _canBindBoth(ports), isTrue);
            }
          })();
        } on Object catch (error) {
          assertion = error;
        }

        expect(assertion, isNotNull);
        expect('$assertion', contains('deliberately thrown assertion'));
      } finally {
        await up.stop();
        _deleteTemp(tmp);
      }
    },
  );

  test('success and failure paths invoke down exactly once', () async {
    final Directory tmp = Directory.systemTemp.createTempSync(
      'device_e2e_up_once',
    );
    final List<int> ports = await _unusedPorts();
    try {
      final String successPidFile = p.join(tmp.path, 'success.pid');
      final DeviceE2eUp success = await _startFixture(
        fixture: fixture,
        packageRoot: packageRoot,
        pidFile: successPidFile,
        ports: ports,
      );
      try {
        await _waitForReady(success);
      } finally {
        await success.stop();
        await success.stop();
      }
      expect(_downCount(successPidFile), 1);

      final String failurePidFile = p.join(tmp.path, 'failure.pid');
      final DeviceE2eUp failure = await _startFixture(
        fixture: fixture,
        packageRoot: packageRoot,
        pidFile: failurePidFile,
        ports: ports,
      );
      Object? assertion;
      try {
        await _waitForReady(failure);
        expect('failure', 'success', reason: 'deliberate suite failure');
      } on Object catch (error) {
        assertion = error;
      } finally {
        await failure.stop();
        await failure.stop();
      }
      expect(assertion, isNotNull);
      expect(_downCount(failurePidFile), 1);
    } finally {
      _deleteTemp(tmp);
    }
  });

  test('failed suite releases both reservations for the next suite', () async {
    final Directory tmp = Directory.systemTemp.createTempSync(
      'device_e2e_up_sequence',
    );
    final List<int> ports = await _unusedPorts();
    try {
      final DeviceE2eUp first = await _startFixture(
        fixture: fixture,
        packageRoot: packageRoot,
        pidFile: p.join(tmp.path, 'first.pid'),
        ports: ports,
      );
      Object? firstFailure;
      try {
        await _waitForReady(first);
        expect(false, isTrue, reason: 'first suite fails deliberately');
      } on Object catch (error) {
        firstFailure = error;
      } finally {
        await first.stop();
      }
      expect(firstFailure, isNotNull);

      final DeviceE2eUp second = await _startFixture(
        fixture: fixture,
        packageRoot: packageRoot,
        pidFile: p.join(tmp.path, 'second.pid'),
        ports: ports,
      );
      try {
        final Map<String, dynamic> ready = await _waitForReady(second);
        expect(ready['event'], 'vm_service_ready');
        expect(await _canBindBoth(ports), isFalse);
      } finally {
        await second.stop();
      }
      expect(await _canBindBoth(ports), isTrue);
    } finally {
      _deleteTemp(tmp);
    }
  });

  test('silent readiness timeout names both gates and empty streams', () async {
    final Directory tmp = Directory.systemTemp.createTempSync(
      'device_e2e_up_silent',
    );
    final String pidFile = p.join(tmp.path, 'silent.pid');
    final DeviceE2eUp up = await DeviceE2eUp.start(
      driveBin: fixture,
      workingDirectory: packageRoot,
      pidFile: pidFile,
      upArguments: const <String>['--silent'],
    );
    Object? failure;
    try {
      await _waitForFile(pidFile);
      try {
        await up.waitForReady(
          timeout: const Duration(milliseconds: 100),
          simulatorUdid: 'SIM-EMPTY-OUTPUT',
          appiumServer: 'http://127.0.0.1:4999',
        );
      } on Object catch (error) {
        failure = error;
      }
      final String diagnostic = '$failure';
      expect(diagnostic, contains('event=vm_service_ready'));
      expect(diagnostic, contains('Flutter VM-service gate'));
      expect(
        diagnostic,
        contains('native LEONARD_HOST_READY/Appium session gate'),
      );
      expect(diagnostic, contains('SIM-EMPTY-OUTPUT'));
      expect(diagnostic, contains('http://127.0.0.1:4999'));
      expect(RegExp(r'<empty>').allMatches(diagnostic).length, 2);
    } finally {
      await up.stop();
      _deleteTemp(tmp);
    }
  });

  test('dual smoke suites delegate up ownership', () {
    _expectOwnerWiring(packageRoot, <String>[
      p.join('integration_test', 'drive', 'drive_dual_e2e_test.dart'),
      p.join('integration_test', 'launch', 'launch_dual_e2e_test.dart'),
    ]);
  });

  test('Auth0 device suites delegate up ownership', () {
    _expectOwnerWiring(packageRoot, <String>[
      p.join('integration_test', 'dogfood', 'dogfood_auth0_e2e_test.dart'),
      p.join(
        'integration_test',
        'dogfood',
        'dogfood_auth0_android_e2e_test.dart',
      ),
    ]);
  });
}

Future<DeviceE2eUp> _startFixture({
  required String fixture,
  required String packageRoot,
  required String pidFile,
  required List<int> ports,
}) => DeviceE2eUp.start(
  driveBin: fixture,
  workingDirectory: packageRoot,
  pidFile: pidFile,
  upArguments: <String>[
    '--simulator-port',
    '${ports[0]}',
    '--appium-port',
    '${ports[1]}',
    '--udid',
    'FIXTURE-SIM-UDID',
  ],
);

Future<Map<String, dynamic>> _waitForReady(DeviceE2eUp up) => up.waitForReady(
  timeout: const Duration(seconds: 20),
  simulatorUdid: 'FIXTURE-SIM-UDID',
  appiumServer: 'http://127.0.0.1:4723',
);

Future<List<int>> _unusedPorts() async {
  final ServerSocket first = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final ServerSocket second = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final List<int> ports = <int>[first.port, second.port];
  await first.close();
  await second.close();
  return ports;
}

Future<bool> _canBindBoth(List<int> ports) async {
  final List<ServerSocket> sockets = <ServerSocket>[];
  try {
    for (final int port in ports) {
      sockets.add(await ServerSocket.bind(InternetAddress.loopbackIPv4, port));
    }
    return true;
  } on SocketException {
    return false;
  } finally {
    for (final ServerSocket socket in sockets) {
      await socket.close();
    }
  }
}

Future<void> _waitForFile(String path) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!File(path).existsSync()) {
    if (stopwatch.elapsed > const Duration(seconds: 10)) {
      throw StateError('fixture did not write pid-file: $path');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

int _downCount(String pidFile) {
  final File countFile = File('$pidFile.down-count');
  if (!countFile.existsSync()) return 0;
  return countFile.readAsLinesSync().length;
}

void _expectOwnerWiring(String packageRoot, List<String> relativePaths) {
  for (final String relativePath in relativePaths) {
    final String source = File(
      p.join(packageRoot, relativePath),
    ).readAsStringSync();
    expect(
      source,
      contains("import '../support/device_e2e_up.dart';"),
      reason: relativePath,
    );
    expect(source, contains('DeviceE2eUp.start('), reason: relativePath);
    expect(source, contains('await up.waitForReady('), reason: relativePath);
    expect(source, contains('await up.stop();'), reason: relativePath);
    expect(source, isNot(contains('final Process up')), reason: relativePath);
    expect(source, isNot(contains('up.kill(')), reason: relativePath);
  }
}

void _deleteTemp(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on Object {
    // Best-effort test cleanup.
  }
}

String _findPackageRoot() {
  Directory directory = Directory.current;
  for (int i = 0; i < 8; i++) {
    final File pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: leonard_cli')) {
      return directory.path;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return p.normalize(p.join(Directory.current.path, 'packages', 'leonard_cli'));
}
