/// Fresh Flutter application launch and VM-service readiness.
library;

import 'dart:async';

import 'package:path/path.dart' as p;

import 'e2e_preflight.dart';
import 'e2e_service.dart';
import 'e2e_session.dart';

/// A held Flutter launch used as the circuit's daemon lease.
class E2eLaunchHandle {
  /// Creates a launch handle.
  const E2eLaunchHandle({
    required this.process,
    required this.deviceId,
    required this.vmUri,
    required this.runDir,
    required this.logPath,
  });

  /// Live Flutter process.
  final E2eChildProcess process;

  /// Selected Flutter device id.
  final String deviceId;

  /// Ready WebSocket VM-service URI.
  final Uri vmUri;

  /// Session artifact directory.
  final String runDir;

  /// Captured Flutter launch log.
  final String logPath;
}

/// Kills stale launchers, reinstalls the app, and waits for its VM-service URI.
Future<E2eLaunchHandle> performE2eLaunch(
  E2eRuntime runtime,
  E2eSessionRequest request,
  E2ePreflight preflight, {
  Duration readyTimeout = const Duration(minutes: 5),
}) async {
  final String deviceId = preflight.device.id;
  try {
    await runtime.runProcess('pkill', <String>['-f', 'run -d $deviceId']);
    await runtime.runProcess('pkill', <String>['-f', 'iproxy.*$deviceId']);
    if (runtime is SystemE2eRuntime) {
      final E2eProcessResult uninstall = await runtime.runProcess(
        'flutter',
        <String>['install', '--uninstall-only', '-d', deviceId],
        workingDirectory: request.appDir,
      );
      if (uninstall.exitCode != 0) {
        throw E2ePhaseFailure(
          E2eFailureCode.launch,
          'e2e launch refused: flutter uninstall exited '
          '${uninstall.exitCode} for $deviceId',
        );
      }
    }
    final String runDir = await runtime.createRunDirectory();
    final String logPath = p.join(runDir, 'flutter.log');
    final E2eChildProcess process = await runtime.startProcess(
      'flutter',
      <String>['run', '-d', deviceId, '--no-devtools'],
      workingDirectory: request.appDir,
      logPath: logPath,
    );
    final Completer<Uri> ready = Completer<Uri>();
    final StreamSubscription<String> output = process.output.listen(
      (String line) {
        final Uri? uri = _vmServiceUri(line);
        if (uri != null && !ready.isCompleted) ready.complete(uri);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!ready.isCompleted) ready.completeError(error, stackTrace);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('flutter output closed'));
        }
      },
    );
    unawaited(
      process.exitCode.then((int code) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('flutter exited with $code'));
        }
      }),
    );
    try {
      final Uri vmUri = await ready.future.timeout(readyTimeout);
      return E2eLaunchHandle(
        process: process,
        deviceId: deviceId,
        vmUri: vmUri,
        runDir: runDir,
        logPath: logPath,
      );
    } on Object {
      await process.kill();
      rethrow;
    } finally {
      await output.cancel();
    }
  } on E2ePhaseFailure {
    rethrow;
  } on Object catch (error) {
    throw E2ePhaseFailure(
      E2eFailureCode.launch,
      'e2e launch failed for $deviceId: $error',
    );
  }
}

Uri? _vmServiceUri(String line) {
  final RegExpMatch? match = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null || !line.toLowerCase().contains('dart vm service')) {
    return null;
  }
  final Uri source = Uri.parse(match.group(0)!);
  final String path = source.path.endsWith('/')
      ? '${source.path}ws'
      : '${source.path}/ws';
  return source.replace(
    scheme: source.scheme == 'https' ? 'wss' : 'ws',
    path: path,
  );
}
