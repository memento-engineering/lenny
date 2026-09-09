/// Real process-tree fixture for DeviceE2eUp lifecycle tests.
///
/// `up` owns two child Dart processes, each holding a loopback socket. `down`
/// reads the same pid-file protocol as leonard_drive and signals the parent,
/// which reaps both children before exiting.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  exitCode = await _run(arguments);
}

Future<int> _run(List<String> arguments) async {
  if (arguments.isEmpty) return 64;
  return switch (arguments.first) {
    'up' => _up(arguments.skip(1).toList()),
    'down' => _down(arguments.skip(1).toList()),
    'child' => _child(arguments.skip(1).toList()),
    _ => 64,
  };
}

Future<int> _up(List<String> arguments) async {
  final String? pidFile = _option(arguments, '--pid-file');
  if (pidFile == null) return 64;
  final bool silent = arguments.contains('--silent');
  final int? simulatorPort = int.tryParse(
    _option(arguments, '--simulator-port') ?? '',
  );
  final int? appiumPort = int.tryParse(
    _option(arguments, '--appium-port') ?? '',
  );
  if (!silent && (simulatorPort == null || appiumPort == null)) return 64;

  final Completer<void> stopRequested = Completer<void>();
  void requestStop(ProcessSignal _) {
    if (!stopRequested.isCompleted) stopRequested.complete();
  }

  final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
      .watch()
      .listen(requestStop);
  StreamSubscription<ProcessSignal>? sigterm;
  try {
    sigterm = ProcessSignal.sigterm.watch().listen(requestStop);
  } on Object {
    // Tests run on POSIX; retain SIGINT as the portable fallback.
  }

  final File ownerPidFile = File(pidFile);
  await ownerPidFile.parent.create(recursive: true);
  await ownerPidFile.writeAsString('$pid\n', flush: true);

  final List<_FixtureChild> children = <_FixtureChild>[];
  try {
    if (!silent) {
      children.add(await _spawnChild(simulatorPort!));
      children.add(await _spawnChild(appiumPort!));
      await Future.wait<void>(<Future<void>>[
        for (final _FixtureChild child in children) child.ready,
      ]);

      final String simulatorUdid =
          _option(arguments, '--udid') ?? 'fixture-simulator';
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'event': 'vm_service_ready',
          'ws_uri': 'ws://127.0.0.1:$simulatorPort/ws',
          'flutter_ws_uri': 'ws://127.0.0.1:$simulatorPort/ws',
          'native_endpoint': 'ws://127.0.0.1:$appiumPort',
          'device_id': simulatorUdid,
          'runner': 'flutter',
          'pid': pid,
        }),
      );
    }

    await stopRequested.future;
  } finally {
    for (final _FixtureChild child in children.reversed) {
      await _stopChild(child);
    }
    await sigint.cancel();
    await sigterm?.cancel();

    try {
      if (ownerPidFile.existsSync()) await ownerPidFile.delete();
    } on Object {
      // Best-effort fixture cleanup.
    }
  }

  if (!silent) {
    stdout.writeln(jsonEncode(<String, String>{'event': 'shutdown'}));
  }
  return 0;
}

Future<int> _down(List<String> arguments) async {
  final String? pidFile = _option(arguments, '--pid-file');
  if (pidFile == null) return 64;

  await File(
    '$pidFile.down-count',
  ).writeAsString('down\n', mode: FileMode.append, flush: true);
  final File file = File(pidFile);
  if (!file.existsSync()) return 1;
  final int? ownerPid = int.tryParse((await file.readAsString()).trim());
  if (ownerPid == null) return 1;
  return Process.killPid(ownerPid, ProcessSignal.sigterm) ? 0 : 1;
}

Future<int> _child(List<String> arguments) async {
  final int? port = int.tryParse(_option(arguments, '--port') ?? '');
  if (port == null) return 64;
  final ServerSocket socket = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    port,
  );
  final Completer<void> stopRequested = Completer<void>();
  void requestStop(ProcessSignal _) {
    if (!stopRequested.isCompleted) stopRequested.complete();
  }

  final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
      .watch()
      .listen(requestStop);
  StreamSubscription<ProcessSignal>? sigterm;
  try {
    sigterm = ProcessSignal.sigterm.watch().listen(requestStop);
  } on Object {
    // Tests run on POSIX; retain SIGINT as the portable fallback.
  }

  stdout.writeln(jsonEncode(<String, Object?>{'event': 'bound', 'port': port}));
  await stopRequested.future;
  await socket.close();
  await sigint.cancel();
  await sigterm?.cancel();
  return 0;
}

Future<_FixtureChild> _spawnChild(int port) async {
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    <String>[Platform.script.toFilePath(), 'child', '--port', '$port'],
  );
  final Completer<void> ready = Completer<void>();
  final Future<void> stdoutDrained = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((String line) {
        try {
          final Object? decoded = jsonDecode(line);
          if (decoded is Map &&
              decoded['event'] == 'bound' &&
              !ready.isCompleted) {
            ready.complete();
          }
        } on FormatException {
          // Ignore non-event fixture output.
        }
      });
  final Future<void> stderrDrained = process.stderr.drain<void>();
  final Future<int> childExitCode = process.exitCode;
  final _FixtureChild child = _FixtureChild(
    process: process,
    ready:
        Future.any<Object>(<Future<Object>>[
          ready.future.then<Object>((_) => true),
          childExitCode.then<Object>((int code) => code),
        ]).then<void>((Object outcome) {
          if (outcome != true) {
            throw StateError(
              'socket child exited before binding (code $outcome)',
            );
          }
        }),
    exitCode: childExitCode,
    stdoutDrained: stdoutDrained,
    stderrDrained: stderrDrained,
  );
  return child;
}

Future<void> _stopChild(_FixtureChild child) async {
  child.process.kill(ProcessSignal.sigterm);
  try {
    await child.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    child.process.kill(ProcessSignal.sigkill);
    await child.exitCode;
  }
  await Future.wait<void>(<Future<void>>[
    child.stdoutDrained,
    child.stderrDrained,
  ]);
}

String? _option(List<String> arguments, String name) {
  final int index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

final class _FixtureChild {
  const _FixtureChild({
    required this.process,
    required this.ready,
    required this.exitCode,
    required this.stdoutDrained,
    required this.stderrDrained,
  });

  final Process process;
  final Future<void> ready;
  final Future<int> exitCode;
  final Future<void> stdoutDrained;
  final Future<void> stderrDrained;
}
