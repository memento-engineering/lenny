/// Stubbed-launcher wiring tier for the native dual launch (AC2, AC6, AC10,
/// AC11). A faked boot is unit/wiring, NOT e2e — this file boots no real
/// processes: it injects a [TargetSpawner] into [launchDualTarget] and builds
/// [DualLaunchHandle] directly via the `forTest` factory, against
/// [_FakeLaunchChannel]s that record their `shutdown` calls. The live two-host
/// boot lives in `launch_dual_e2e_test.dart`.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:leonard_cli/src/launcher.dart';
import 'package:test/test.dart';

/// A [LaunchChannel] that records its `shutdown` calls (a no-op — no real
/// `q`/SIGTERM). Optionally completes its `shutdown` future only when released,
/// so a test can assert serial teardown order.
class _FakeLaunchChannel implements LaunchChannel {
  _FakeLaunchChannel(String ws, {this.label = 'channel', this.onShutdown})
    : wsUri = Uri.parse(ws);

  final String label;
  final void Function(Duration grace)? onShutdown;

  @override
  final Uri wsUri;

  final Completer<int> _exit = Completer<int>();

  /// Simulate the channel's process exiting with [code] (drives [exitCode] /
  /// the composite's `Future.any` without a `shutdown`).
  void completeExit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  final List<Duration> shutdownGraces = <Duration>[];
  int shutdownCalls = 0;

  @override
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) async {
    shutdownCalls++;
    shutdownGraces.add(grace);
    onShutdown?.call(grace);
    if (!_exit.isCompleted) _exit.complete(0);
  }
}

/// A local HTTP server that answers `GET /status` 200 so [launchDualTarget]'s
/// Appium pre-flight probe passes without a real Appium server.
Future<HttpServer> _fakeAppium() async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest req) async {
    req.response.statusCode = 200;
    req.response.write('{"value":{}}');
    await req.response.close();
  });
  return server;
}

void main() {
  group('DualLaunchHandle.forTest exposes the dual endpoints (AC2)', () {
    test('flutter/native ws URIs + the shared deviceId', () {
      final _FakeLaunchChannel flutter = _FakeLaunchChannel(
        'ws://127.0.0.1:1111/ws',
      );
      final _FakeLaunchChannel native = _FakeLaunchChannel(
        'ws://127.0.0.1:2222/ws',
      );
      final DualLaunchHandle h = DualLaunchHandle.forTest(
        flutter: flutter,
        native: native,
        deviceId: 'SIM-UDID-ABC',
      );
      expect(h.flutter.wsUri.toString(), 'ws://127.0.0.1:1111/ws');
      expect(h.native.wsUri.toString(), 'ws://127.0.0.1:2222/ws');
      expect(h.flutterWsUri.toString(), 'ws://127.0.0.1:1111/ws');
      expect(h.nativeEndpoint.toString(), 'ws://127.0.0.1:2222/ws');
      expect(h.deviceId, 'SIM-UDID-ABC');
    });
  });

  group('launchDualTarget wiring via injected spawn', () {
    test(
      'threads the SAME udid into the flutter device + native --udid (AC2)',
      () async {
        final HttpServer appium = await _fakeAppium();
        addTearDown(() => appium.close(force: true));
        const String udid = 'SIM-SHARED-UDID';
        String? flutterDevice;
        List<String>? nativeExtraArgs;

        Future<LaunchChannel> fakeSpawn({
          required TargetRunner runner,
          required String entrypoint,
          String? device,
          bool disableAuthCodes = false,
          List<String> extraArgs = const <String>[],
          String? readyLine,
          required void Function(String) onLog,
          required Duration timeout,
        }) async {
          if (runner == TargetRunner.flutter) {
            flutterDevice = device;
            return _FakeLaunchChannel(
              'ws://127.0.0.1:1111/ws',
              label: 'flutter',
            );
          }
          nativeExtraArgs = extraArgs;
          // The native leg MUST be gated on LEONARD_HOST_READY.
          expect(readyLine, 'LEONARD_HOST_READY');
          return _FakeLaunchChannel('ws://127.0.0.1:2222/ws', label: 'native');
        }

        final DualLaunchHandle h = await launchDualTarget(
          flutterEntrypoint: 'lib/main.dart',
          udid: udid,
          app: '/path/Runner.app',
          nativeHostPath: 'bin/leonard_native_host.dart',
          appiumServer: Uri.parse('http://127.0.0.1:${appium.port}'),
          onLog: (_) {},
          spawn: fakeSpawn,
        );

        expect(
          flutterDevice,
          udid,
          reason: 'flutter -d must be the shared udid',
        );
        expect(
          nativeExtraArgs,
          containsAllInOrder(<String>['--udid', udid]),
          reason: 'native --udid must be the same shared udid',
        );
        expect(h.deviceId, udid);
        expect(h.flutterWsUri.toString(), 'ws://127.0.0.1:1111/ws');
        expect(h.nativeEndpoint.toString(), 'ws://127.0.0.1:2222/ws');
      },
    );

    test(
      'native-boot failure tears down the flutter channel, bounded (AC6)',
      () async {
        final HttpServer appium = await _fakeAppium();
        addTearDown(() => appium.close(force: true));
        late _FakeLaunchChannel flutter;

        Future<LaunchChannel> fakeSpawn({
          required TargetRunner runner,
          required String entrypoint,
          String? device,
          bool disableAuthCodes = false,
          List<String> extraArgs = const <String>[],
          String? readyLine,
          required void Function(String) onLog,
          required Duration timeout,
        }) async {
          if (runner == TargetRunner.flutter) {
            flutter = _FakeLaunchChannel('ws://127.0.0.1:1111/ws');
            return flutter;
          }
          // The native leg fails AFTER the flutter leg already succeeded.
          throw StateError(
            'native host exited (code 1) before LEONARD_HOST_READY',
          );
        }

        await expectLater(
          launchDualTarget(
            flutterEntrypoint: 'lib/main.dart',
            udid: 'SIM',
            app: '/path/Runner.app',
            nativeHostPath: 'bin/leonard_native_host.dart',
            appiumServer: Uri.parse('http://127.0.0.1:${appium.port}'),
            onLog: (_) {},
            spawn: fakeSpawn,
          ),
          throwsA(isA<StateError>()),
        );
        expect(flutter.shutdownCalls, 1, reason: 'no leaked flutter process');
        expect(
          flutter.shutdownGraces.single,
          const Duration(seconds: 2),
          reason: 'compensation grace is bounded to 2s',
        );
      },
    );
  });

  group('DualLaunchHandle.shutdown teardown order + ownership', () {
    test(
      'serial native->flutter (native fully resolves first) (AC10)',
      () async {
        final List<String> events = <String>[];

        // A native channel whose shutdown takes a real async tick to resolve. If
        // teardown were concurrent (not serial), flutter would record before
        // native's delayed body finishes and the order assertion would fail.
        final _SlowChannel native = _SlowChannel(
          'ws://127.0.0.1:2222/ws',
          delay: const Duration(milliseconds: 50),
          onResolved: () => events.add('native'),
        );
        final _FakeLaunchChannel flutter = _FakeLaunchChannel(
          'ws://127.0.0.1:1111/ws',
          label: 'flutter',
          onShutdown: (_) => events.add('flutter'),
        );

        final DualLaunchHandle h = DualLaunchHandle.forTest(
          flutter: flutter,
          native: native,
          deviceId: 'SIM',
        );

        await h.shutdown();
        // native's body fully resolves BEFORE flutter begins.
        expect(events, <String>['native', 'flutter']);
      },
    );

    test('every leg runs even when native.shutdown throws (AC10)', () async {
      final List<String> events = <String>[];
      final _FakeLaunchChannel native = _ThrowingChannel('ws://x/ws');
      final _FakeLaunchChannel flutter = _FakeLaunchChannel(
        'ws://127.0.0.1:1111/ws',
        onShutdown: (_) => events.add('flutter'),
      );
      final DualLaunchHandle h = DualLaunchHandle.forTest(
        flutter: flutter,
        native: native,
        deviceId: 'SIM',
      );
      await h.shutdown(); // must not throw — teardown swallows
      expect(
        events,
        contains('flutter'),
        reason: 'flutter leg still runs after native throws',
      );
    });

    test('owned:false: sim hook never fires; idempotent (AC11)', () async {
      final List<String> simctlCalls = <String>[];
      final _FakeLaunchChannel native = _FakeLaunchChannel('ws://n/ws');
      final _FakeLaunchChannel flutter = _FakeLaunchChannel('ws://f/ws');
      final DualLaunchHandle h = DualLaunchHandle.forTest(
        flutter: flutter,
        native: native,
        deviceId: 'SIM',
        owned: false,
        simctlShutdown: (String udid) async => simctlCalls.add(udid),
      );
      await h.shutdown();
      await h.shutdown(); // idempotent: memoized — each leg runs exactly once
      expect(
        simctlCalls,
        isEmpty,
        reason: 'attach default never shuts the operator-owned sim',
      );
      expect(native.shutdownCalls, 1, reason: 'idempotent: native runs once');
      expect(flutter.shutdownCalls, 1, reason: 'idempotent: flutter runs once');
    });

    // owned:true runs the (injected, here recording) sim-shutdown hook LAST,
    // after native + flutter, exactly once. The real `xcrun simctl shutdown`
    // hook is exercised behind the env gate in launch_dual_e2e_test.dart (T2).
    test('owned:true: sim hook runs LAST, exactly once (AC10/AC11)', () async {
      final List<String> events = <String>[];
      // A slow native leg: were teardown concurrent, 'sim' could race ahead.
      final _SlowChannel native = _SlowChannel(
        'ws://127.0.0.1:2222/ws',
        delay: const Duration(milliseconds: 30),
        onResolved: () => events.add('native'),
      );
      final _FakeLaunchChannel flutter = _FakeLaunchChannel(
        'ws://127.0.0.1:1111/ws',
        label: 'flutter',
        onShutdown: (_) => events.add('flutter'),
      );
      String? simUdid;
      final DualLaunchHandle h = DualLaunchHandle.forTest(
        flutter: flutter,
        native: native,
        deviceId: 'SIM-OWNED',
        owned: true,
        simctlShutdown: (String udid) async {
          simUdid = udid;
          events.add('sim');
        },
      );
      await h.shutdown();
      expect(
        events,
        <String>['native', 'flutter', 'sim'],
        reason: 'serial dependency-reverse teardown: sim shutdown runs last',
      );
      expect(simUdid, 'SIM-OWNED', reason: 'sim hook gets the shared udid');
    });
  });

  group('DualLaunchHandle.exitCode fires when EITHER channel exits', () {
    test('resolves with the first channel exit (Future.any)', () async {
      final _FakeLaunchChannel flutter = _FakeLaunchChannel('ws://f/ws');
      final _FakeLaunchChannel native = _FakeLaunchChannel('ws://n/ws');
      final DualLaunchHandle h = DualLaunchHandle.forTest(
        flutter: flutter,
        native: native,
        deviceId: 'SIM',
      );
      native.completeExit(7); // the native child dies first
      expect(
        await h.exitCode,
        7,
        reason: 'composite exitCode = Future.any([flutter, native])',
      );
    });
  });

  group('launchTarget readyLine failure path (blocker regression)', () {
    test('gated readyLine failure leaks no unhandled async error', () async {
      // Force the wsUri-await-fails-FIRST path: a near-zero timeout trips
      // before the dart VM scrapes its service URL, so launchTarget throws at
      // the `await wsUri.future.timeout` and the gated `ready` completer's
      // await (the next line) is NEVER reached. When the SIGTERM'd child then
      // exits, the exit handler calls `ready.completeError(...)` — pre-fix on a
      // future with no listener, surfacing as a root-zone UNHANDLED async error
      // (exit 255) that raced the clean exit-1 mapping. We assert ONLY that no
      // unhandled error escapes the zone; the thrown error TYPE is incidental
      // (TimeoutException here), and a slow but valid target keeps the repro
      // independent of compile timing. (A compile-error target would NOT
      // repro: `dart run` prints its service URL BEFORE compiling the script,
      // so wsUri completes first and `ready` does get its await listener.)
      final Directory dir = await Directory.systemTemp.createTemp(
        'm4_readyline_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final File slow = File('${dir.path}/slow_target.dart');
      await slow.writeAsString(
        'void main() async '
        '{ await Future<void>.delayed(const Duration(seconds: 5)); }\n',
      );

      Object? zoneError;
      await runZonedGuarded(() async {
        await expectLater(
          launchTarget(
            runner: TargetRunner.dart,
            entrypoint: slow.path,
            readyLine: 'LEONARD_HOST_READY',
            onLog: (_) {},
            timeout: const Duration(milliseconds: 1),
          ),
          throwsA(anything),
        );
      }, (Object e, StackTrace st) => zoneError ??= e);
      // The orphan (if any) fires when the SIGTERM'd child finally exits, after
      // the zone body has already returned — the zone still captures it. Wait
      // out that window before asserting absence.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        zoneError,
        isNull,
        reason: 'a gated readyLine failure must not leak an unhandled error',
      );
    });
  });
}

/// A channel whose `shutdown` throws — to prove later legs still run.
class _ThrowingChannel extends _FakeLaunchChannel {
  _ThrowingChannel(super.ws) : super(label: 'throwing');

  @override
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) async {
    shutdownCalls++;
    throw StateError('native teardown blew up');
  }
}

/// A channel whose `shutdown` takes a real async [delay] to resolve, so a
/// concurrent (non-serial) teardown would be observable as out-of-order.
class _SlowChannel extends _FakeLaunchChannel {
  _SlowChannel(super.ws, {required this.delay, required this.onResolved})
    : super(label: 'slow');

  final Duration delay;
  final void Function() onResolved;

  @override
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) async {
    shutdownCalls++;
    shutdownGraces.add(grace);
    await Future<void>.delayed(delay);
    onResolved();
  }
}
