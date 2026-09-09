/// Owns a device e2e `leonard_drive up` process and its pid-file teardown.
///
/// The owner drains both output pipes for the lifetime of `up`, reports the
/// two readiness gates with bounded output history, and memoizes [stop] so all
/// successful and exceptional paths converge on one awaited `down` command.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A running device-e2e `up` command whose complete process tree is owned.
final class DeviceE2eUp {
  DeviceE2eUp._({
    required Process process,
    required String driveBin,
    required String downWorkingDirectory,
    required String pidFile,
  }) : _process = process,
       _driveBin = driveBin,
       _downWorkingDirectory = downWorkingDirectory,
       _pidFile = pidFile,
       _exitCode = process.exitCode;

  static const int _retainedLineCount = 50;
  static const Duration _gracefulExitTimeout = Duration(seconds: 60);
  static const Duration _signalExitTimeout = Duration(seconds: 5);

  final Process _process;
  final String _driveBin;
  final String _downWorkingDirectory;
  final String _pidFile;
  final Future<int> _exitCode;
  final Completer<Map<String, dynamic>> _ready =
      Completer<Map<String, dynamic>>();
  final Completer<void> _shutdownSeen = Completer<void>();
  final List<String> _stdoutLines = <String>[];
  final List<String> _stderrLines = <String>[];

  late final Future<void> _stdoutDrained;
  late final Future<void> _stderrDrained;
  Future<void>? _stopFuture;

  /// Starts `dart run <driveBin> up`, adding the owner pid-file argument.
  ///
  /// [workingDirectory] is the target project used by `up`; the down command
  /// runs from [downWorkingDirectory] when supplied so callers can preserve
  /// the CLI package context used by their existing teardown.
  static Future<DeviceE2eUp> start({
    required String driveBin,
    required String workingDirectory,
    required String pidFile,
    required List<String> upArguments,
    String? downWorkingDirectory,
  }) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', driveBin, 'up', ...upArguments, '--pid-file', pidFile],
      workingDirectory: workingDirectory,
    );
    final DeviceE2eUp owner = DeviceE2eUp._(
      process: process,
      driveBin: driveBin,
      downWorkingDirectory: downWorkingDirectory ?? workingDirectory,
      pidFile: pidFile,
    );
    owner._stdoutDrained = owner._drainStdout();
    owner._stderrDrained = owner._drainStderr();
    return owner;
  }

  /// The most recent 50 stdout lines, oldest first.
  List<String> get stdoutLines => List<String>.unmodifiable(_stdoutLines);

  /// The most recent 50 stderr lines, oldest first.
  List<String> get stderrLines => List<String>.unmodifiable(_stderrLines);

  /// Completes when the owned `up` process exits.
  Future<int> get exitCode => _exitCode;

  /// Completes when `up` emits its machine-readable shutdown event.
  Future<void> get shutdownSeen => _shutdownSeen.future;

  /// Waits for the parsed `event=vm_service_ready` envelope.
  ///
  /// Readiness is raced against both process exit and [timeout]. Every failure
  /// identifies the concrete device and Appium endpoint, both readiness gates,
  /// and the retained stdout/stderr tails (including explicit empty markers).
  Future<Map<String, dynamic>> waitForReady({
    required Duration timeout,
    required String simulatorUdid,
    required String appiumServer,
  }) async {
    final Object outcome = await Future.any<Object>(<Future<Object>>[
      _ready.future.then<Object>(_Ready.new),
      _exitBeforeReady(),
      Future<Object>.delayed(timeout, () => const _ReadinessTimedOut()),
    ]);
    return switch (outcome) {
      _Ready(:final envelope) => envelope,
      _UpExited(:final code) => throw StateError(
        _readinessFailure(
          'exited with code $code',
          simulatorUdid: simulatorUdid,
          appiumServer: appiumServer,
        ),
      ),
      _ReadinessTimedOut() => throw StateError(
        _readinessFailure(
          'did not become ready within ${timeout.inMilliseconds} ms',
          simulatorUdid: simulatorUdid,
          appiumServer: appiumServer,
        ),
      ),
      _ => throw StateError('unreachable readiness outcome: $outcome'),
    };
  }

  /// Reaps the complete tree through `down --pid-file`, exactly once.
  ///
  /// A cooperative exit gets 60 seconds. SIGTERM and then SIGKILL are only
  /// used if the `up` owner itself does not exit; this future never completes
  /// until its exit code and both drained output streams have completed.
  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    try {
      await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        _driveBin,
        'down',
        '--pid-file',
        _pidFile,
      ], workingDirectory: _downWorkingDirectory);
    } on Object {
      // The fallback signals below still guarantee that the owner cannot leak.
    }

    if (await _waitForExit(_gracefulExitTimeout)) return;

    _process.kill(ProcessSignal.sigterm);
    if (await _waitForExit(_signalExitTimeout)) return;

    _process.kill(ProcessSignal.sigkill);
    await _exitAndDrains;
  }

  Future<Object> _exitBeforeReady() async {
    final int code = await _exitCode;
    // Process exit can beat delivery of its final pipe bytes. Drain both before
    // diagnosing it so a valid last envelope wins and final stderr is shown.
    await Future.wait<void>(<Future<void>>[_stdoutDrained, _stderrDrained]);
    if (_ready.isCompleted) return _Ready(await _ready.future);
    return _UpExited(code);
  }

  Future<bool> _waitForExit(Duration timeout) async {
    try {
      await _exitAndDrains.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> get _exitAndDrains => Future.wait<void>(<Future<void>>[
    _exitCode.then<void>((_) {}),
    _stdoutDrained,
    _stderrDrained,
  ]);

  Future<void> _drainStdout() => _drain(
    _process.stdout,
    _stdoutLines,
    onLine: (String line) {
      try {
        final Object? decoded = jsonDecode(line);
        if (decoded is! Map) return;
        if (decoded['event'] == 'vm_service_ready' && !_ready.isCompleted) {
          _ready.complete(decoded.cast<String, dynamic>());
        }
        if (decoded['event'] == 'shutdown' && !_shutdownSeen.isCompleted) {
          _shutdownSeen.complete();
        }
      } on FormatException {
        // Human-readable target output is retained but is not an event.
      }
    },
  );

  Future<void> _drainStderr() => _drain(_process.stderr, _stderrLines);

  Future<void> _drain(
    Stream<List<int>> stream,
    List<String> destination, {
    void Function(String line)? onLine,
  }) async {
    try {
      await stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) {
            _retain(destination, line);
            onLine?.call(line);
          });
    } on Object catch (error) {
      _retain(destination, '<stream error: $error>');
    }
  }

  void _retain(List<String> destination, String line) {
    destination.add(line);
    if (destination.length > _retainedLineCount) {
      destination.removeAt(0);
    }
  }

  String _readinessFailure(
    String failure, {
    required String simulatorUdid,
    required String appiumServer,
  }) =>
      'up $failure before event=vm_service_ready.\n'
      'Simulator UDID: $simulatorUdid\n'
      'Appium server: $appiumServer\n'
      'Readiness requires both the Flutter VM-service gate and the native '
      'LEONARD_HOST_READY/Appium session gate.\n'
      'up stdout (last $_retainedLineCount lines):\n'
      '${_render(_stdoutLines)}\n'
      'up stderr (last $_retainedLineCount lines):\n'
      '${_render(_stderrLines)}';

  String _render(List<String> lines) =>
      lines.isEmpty ? '<empty>' : lines.join('\n');
}

final class _Ready {
  const _Ready(this.envelope);

  final Map<String, dynamic> envelope;
}

final class _UpExited {
  const _UpExited(this.code);

  final int code;
}

final class _ReadinessTimedOut {
  const _ReadinessTimedOut();
}
