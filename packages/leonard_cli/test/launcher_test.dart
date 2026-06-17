import 'package:leonard_cli/src/launcher.dart';
import 'package:test/test.dart';

void main() {
  group('parseVmServiceWsUri', () {
    test('flutter run line -> ws URI with token preserved', () {
      const line =
          'A Dart VM Service on iPhone 15 is available at: '
          'http://127.0.0.1:50123/abcDEF123=/';
      expect(
        parseVmServiceWsUri(line).toString(),
        'ws://127.0.0.1:50123/abcDEF123=/ws',
      );
    });

    test('dart run line -> ws URI', () {
      const line =
          'The Dart VM service is listening on http://127.0.0.1:8181/xyz=/';
      expect(
        parseVmServiceWsUri(line).toString(),
        'ws://127.0.0.1:8181/xyz=/ws',
      );
    });

    test('token-free URL collapses to /ws', () {
      expect(
        parseVmServiceWsUri('listening on http://127.0.0.1:8181/').toString(),
        'ws://127.0.0.1:8181/ws',
      );
    });

    test('localhost host is accepted', () {
      expect(
        parseVmServiceWsUri('http://localhost:8181/tok/').toString(),
        'ws://localhost:8181/tok/ws',
      );
    });

    test('https -> wss', () {
      expect(
        parseVmServiceWsUri('at https://127.0.0.1:8181/tok/').toString(),
        'wss://127.0.0.1:8181/tok/ws',
      );
    });

    test('a non-service line returns null', () {
      expect(parseVmServiceWsUri('Running Gradle task...'), isNull);
    });

    test('a non-loopback URL (doc link) is not mistaken for the service', () {
      expect(
        parseVmServiceWsUri('See https://docs.flutter.dev/run for help'),
        isNull,
      );
    });
  });

  group('buildRunnerInvocation', () {
    test('flutter with device', () {
      final inv = buildRunnerInvocation(
        runner: TargetRunner.flutter,
        entrypoint: 'lib/main.dart',
        device: 'iPhone 15',
      );
      expect(inv.executable, 'flutter');
      expect(inv.args, <String>[
        'run',
        '-d',
        'iPhone 15',
        '-t',
        'lib/main.dart',
      ]);
    });

    test('flutter without device omits -d', () {
      final inv = buildRunnerInvocation(
        runner: TargetRunner.flutter,
        entrypoint: 'lib/main.dart',
      );
      expect(inv.args, <String>['run', '-t', 'lib/main.dart']);
    });

    test('dart runner (default port, auth codes on)', () {
      final inv = buildRunnerInvocation(
        runner: TargetRunner.dart,
        entrypoint: 'bin/host.dart',
      );
      expect(inv.executable, 'dart');
      expect(inv.args, <String>[
        'run',
        '--enable-vm-service=0',
        'bin/host.dart',
      ]);
    });

    test('dart runner with explicit port + disabled auth codes', () {
      final inv = buildRunnerInvocation(
        runner: TargetRunner.dart,
        entrypoint: 'bin/host.dart',
        vmServicePort: 1234,
        disableAuthCodes: true,
      );
      expect(inv.args, <String>[
        'run',
        '--enable-vm-service=1234',
        '--disable-service-auth-codes',
        'bin/host.dart',
      ]);
    });

    test('a device with the dart runner is a hard error (no dual mode)', () {
      expect(
        () => buildRunnerInvocation(
          runner: TargetRunner.dart,
          entrypoint: 'bin/host.dart',
          device: 'iPhone 15',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty entrypoint is rejected', () {
      expect(
        () =>
            buildRunnerInvocation(runner: TargetRunner.flutter, entrypoint: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
