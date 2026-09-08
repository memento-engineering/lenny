/// Process-level regressions for fail-soft frame capture in the live CLI.
///
/// The launched target is a test-only pure-Dart core-extension double. It
/// registers the same VM-service method names the driver calls, including
/// explicit `core.wait` and `core.done` action methods; production
/// `ExplorationHost` deliberately does not provide Flutter's core tools.
@Timeout(Duration(seconds: 150))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leonard_cli/src/file_trajectory_sink.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'capture-only run skips malformed frame and keeps later frame',
    () async {
      final List<int> validPng = await File(
        p.join('test', 'image_goldens', 'reference.png'),
      ).readAsBytes();
      final _LiveRun run = await _LiveRun.start(
        screenshots: <String>['!', base64Encode(validPng)],
      );
      addTearDown(run.dispose);

      final _ProcessResult result = await run.waitForExit();

      expect(result.exitCode, 0, reason: result.stderr);
      final List<Map<String, dynamic>> turns = await _turnsIn(run.outputPath);
      expect(turns, hasLength(2));
      expect(turns.map((turn) => turn['index']), <int>[0, 1]);
      expect(
        turns.map((turn) => (turn['observation'] as Map)['screenshot_png_b64']),
        <String>['!', base64Encode(validPng)],
      );

      final String firstFrame = p.join(run.framesDirectory, 'turn-0000.png');
      final String laterFrame = p.join(run.framesDirectory, 'turn-0001.png');
      expect(await File(firstFrame).exists(), isFalse);
      expect(await File(laterFrame).readAsBytes(), validPng);
      final List<String> warnings = _captureWarnings(result.stderr);
      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        startsWith(
          'warning: frame capture skipped turn 0: FormatException: '
          'Invalid character',
        ),
      );
      expect(run.server.requestCount, 2);
    },
  );

  test('capture-only run skips frames-directory write failures', () async {
    final List<int> validPng = await File(
      p.join('test', 'image_goldens', 'reference.png'),
    ).readAsBytes();
    final String screenshot = base64Encode(validPng);
    final _LiveRun run = await _LiveRun.start(
      screenshots: <String>[screenshot, screenshot],
      blockFramesDirectory: true,
    );
    addTearDown(run.dispose);

    final _ProcessResult result = await run.waitForExit();

    expect(result.exitCode, 0, reason: result.stderr);
    final List<Map<String, dynamic>> turns = await _turnsIn(run.outputPath);
    expect(turns, hasLength(2));
    expect(turns.map((turn) => turn['index']), <int>[0, 1]);
    expect(
      turns.map((turn) => (turn['observation'] as Map)['screenshot_png_b64']),
      <String>[screenshot, screenshot],
    );
    expect(
      await FileSystemEntity.type(run.framesDirectory),
      FileSystemEntityType.file,
    );
    expect(
      await File(p.join(run.framesDirectory, 'turn-0000.png')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(run.framesDirectory, 'turn-0001.png')).exists(),
      isFalse,
    );
    final List<String> warnings = _captureWarnings(result.stderr);
    expect(warnings, hasLength(2));
    expect(warnings[0], startsWith('warning: frame capture skipped turn 0: '));
    expect(warnings[1], startsWith('warning: frame capture skipped turn 1: '));
    expect(warnings.every((line) => !line.contains('\r')), isTrue);
    expect(run.server.requestCount, 2);
  });
}

List<String> _captureWarnings(String stderr) => const LineSplitter()
    .convert(stderr)
    .where(
      (String line) => line.startsWith('warning: frame capture skipped turn '),
    )
    .toList(growable: false);

Future<List<Map<String, dynamic>>> _turnsIn(String trajectoryPath) async {
  final List<String> lines = await File(trajectoryPath).readAsLines();
  return <Map<String, dynamic>>[
    for (final String line in lines)
      if (jsonDecode(line) case final Map<String, dynamic> record)
        if (record['type'] == 'turn') record,
  ];
}

class _LiveRun {
  _LiveRun._({
    required this.temp,
    required this.server,
    required this.process,
    required this.targetProcess,
    required this.outputPath,
    required this.framesDirectory,
    required Future<String> stdoutText,
    required Future<String> stderrText,
    required Future<void> targetStdoutDone,
    required Future<void> targetStderrDone,
  }) : _stdoutText = stdoutText,
       _stderrText = stderrText,
       _targetStdoutDone = targetStdoutDone,
       _targetStderrDone = targetStderrDone;

  final Directory temp;
  final _ScriptedSwiftInferServer server;
  final Process process;
  final Process targetProcess;
  final String outputPath;
  final String framesDirectory;
  final Future<String> _stdoutText;
  final Future<String> _stderrText;
  final Future<void> _targetStdoutDone;
  final Future<void> _targetStderrDone;

  static Future<_LiveRun> start({
    required List<String> screenshots,
    bool blockFramesDirectory = false,
  }) async {
    final String packageRoot = _findPackageRoot();
    final Directory temp = await Directory.systemTemp.createTemp(
      'leonard-frame-run-',
    );
    final _ScriptedSwiftInferServer server =
        await _ScriptedSwiftInferServer.start();
    Process? process;
    Process? targetProcess;
    Future<void>? targetStdoutDone;
    Future<void>? targetStderrDone;
    final String outputPath = p.join(temp.path, 'run.jsonl');
    final String framesDirectory = FileTrajectorySink.framesDirectoryFor(
      outputPath,
    );
    final String targetPath = p.join(temp.path, 'fake_core_target.dart');
    try {
      await File(
        targetPath,
      ).writeAsString(_fakeCoreTarget(screenshots: screenshots), flush: true);
      if (blockFramesDirectory) {
        await File(
          framesDirectory,
        ).writeAsString('not a directory', flush: true);
      }
      targetProcess = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '--enable-vm-service=0',
        targetPath,
      ], workingDirectory: packageRoot);
      final List<String> targetStdout = <String>[];
      final List<String> targetStderr = <String>[];
      final Completer<String> vmServiceReady = Completer<String>();
      targetStdoutDone = targetProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) {
            targetStdout.add(line);
            final Object? decoded;
            try {
              decoded = jsonDecode(line);
            } on FormatException {
              return;
            }
            if (decoded case <String, dynamic>{
              'event': 'vm_service_ready',
              'ws_uri': final String wsUri,
            }) {
              if (!vmServiceReady.isCompleted && wsUri.isNotEmpty) {
                vmServiceReady.complete(wsUri);
              }
            }
          });
      targetStderrDone = targetProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(targetStderr.add);
      unawaited(
        targetProcess.exitCode.then((int code) {
          if (!vmServiceReady.isCompleted) {
            vmServiceReady.completeError(
              StateError('fake target exited with code $code before ready'),
            );
          }
        }),
      );

      final String vmUri;
      try {
        vmUri = await vmServiceReady.future.timeout(
          const Duration(seconds: 30),
        );
      } on Object catch (cause) {
        targetProcess.kill(ProcessSignal.sigkill);
        await targetProcess.exitCode;
        await targetStdoutDone;
        await targetStderrDone;
        throw StateError(
          'fake target did not emit a registered-extension VM-service URI: '
          '$cause\nstdout:\n${targetStdout.join('\n')}\n'
          'stderr:\n${targetStderr.join('\n')}',
        );
      }
      await _waitForLeonardContract(packageRoot: packageRoot, vmUri: vmUri);

      process = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'run',
          p.join(packageRoot, 'bin', 'leonard_cli.dart'),
          '--vm-uri',
          vmUri,
          '--goal',
          'exercise frame capture',
          '--output',
          outputPath,
          '--model',
          'qwen-mlx',
          '--model-id',
          'frame-capture-text-only-test',
        ],
        workingDirectory: packageRoot,
        environment: <String, String>{
          ...Platform.environment,
          'SWIFT_INFER_ENDPOINT': server.endpoint.toString(),
        },
      );
      return _LiveRun._(
        temp: temp,
        server: server,
        process: process,
        targetProcess: targetProcess,
        outputPath: outputPath,
        framesDirectory: framesDirectory,
        stdoutText: process.stdout.transform(utf8.decoder).join(),
        stderrText: process.stderr.transform(utf8.decoder).join(),
        targetStdoutDone: targetStdoutDone,
        targetStderrDone: targetStderrDone,
      );
    } on Object {
      process?.kill(ProcessSignal.sigkill);
      targetProcess?.kill(ProcessSignal.sigkill);
      await process?.exitCode;
      await targetProcess?.exitCode;
      await targetStdoutDone;
      await targetStderrDone;
      await server.close();
      if (await temp.exists()) await temp.delete(recursive: true);
      rethrow;
    }
  }

  Future<_ProcessResult> waitForExit() async {
    final int exitCode = await process.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('leonard_cli did not exit within 120 seconds');
      },
    );
    return _ProcessResult(
      exitCode: exitCode,
      stdout: await _stdoutText,
      stderr: await _stderrText,
    );
  }

  Future<void> dispose() async {
    process.kill(ProcessSignal.sigkill);
    targetProcess.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await targetProcess.exitCode;
    await _targetStdoutDone;
    await _targetStderrDone;
    await server.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  }
}

Future<void> _waitForLeonardContract({
  required String packageRoot,
  required String vmUri,
}) async {
  final String driveBin = p.join(packageRoot, 'bin', 'leonard_drive.dart');
  ProcessResult? finalResult;
  for (var attempt = 0; attempt < 20; attempt++) {
    finalResult = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      driveBin,
      'tools',
      '--vm-uri',
      vmUri,
    ], workingDirectory: packageRoot);
    if (finalResult.exitCode == 0 &&
        _reportsLeonardContract(finalResult.stdout as String)) {
      return;
    }
    if (attempt < 19) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError(
    'Leonard contract was not ready after 20 attempts\n'
    'stdout:\n${finalResult?.stdout}\n'
    'stderr:\n${finalResult?.stderr}',
  );
}

bool _reportsLeonardContract(String stdoutText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stdoutText);
  } on FormatException {
    return false;
  }
  if (decoded is! Map<String, dynamic>) return false;
  final Object? namespaces = decoded['namespaces'];
  if (namespaces is! List) return false;
  for (final Object? entry in namespaces) {
    if (entry is! Map || entry['namespace'] != 'core') continue;
    final Object? tools = entry['tools'];
    if (tools is List && tools.contains('wait') && tools.contains('done')) {
      return true;
    }
  }
  return false;
}

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ScriptedSwiftInferServer {
  _ScriptedSwiftInferServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  int requestCount = 0;

  static Future<_ScriptedSwiftInferServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    return _ScriptedSwiftInferServer._(server);
  }

  Uri get endpoint =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  Future<void> _handle(HttpRequest request) async {
    await request.drain<void>();
    final int turn = requestCount++;
    final bool done = turn > 0;
    final String toolName = done ? 'core_done' : 'core_wait';
    final Map<String, Object?> args = done
        ? <String, Object?>{'reason': 'frame capture complete'}
        : <String, Object?>{'seconds': 0};
    final List<Map<String, Object?>> events = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'message_start',
        'message': <String, Object?>{
          'id': 'msg_$turn',
          'model': 'frame-capture-text-only-test',
        },
      },
      <String, Object?>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, Object?>{
          'type': 'tool_use',
          'id': 'toolu_$turn',
          'name': toolName,
          'input': args,
        },
      },
      <String, Object?>{'type': 'content_block_stop', 'index': 0},
      <String, Object?>{
        'type': 'message_delta',
        'delta': <String, Object?>{'stop_reason': 'tool_use'},
      },
      <String, Object?>{'type': 'message_stop'},
    ];
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    for (final Map<String, Object?> event in events) {
      request.response.write('data: ${jsonEncode(event)}\n\n');
    }
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

String _fakeCoreTarget({required List<String> screenshots}) {
  final String encodedScreenshots = screenshots.map(jsonEncode).join(', ');
  return '''
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

Future<void> main() async {
  final List<String> screenshots = <String>[$encodedScreenshots];
  var observationIndex = 0;

  developer.registerExtension('ext.leonard.core.handshake', (_, __) async {
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'protocolVersion': '2',
      'bindingType': 'FrameCaptureTestCore',
      'extensions': [
        {'namespace': 'core', 'tools': ['wait', 'done']},
      ],
      'capabilities': ['screenshot'],
    }));
  });
  developer.registerExtension(
    'ext.leonard.core.get_stable_observation',
    (_, __) async {
      final int index = observationIndex < screenshots.length
          ? observationIndex++
          : screenshots.length - 1;
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'type': 'Observation',
        'value': {
          'semantics': [],
          'routes': [],
          'errors': [],
          'stability': {
            'policy': 'action-relative',
            'terminated_by': 'idle',
            'duration_ms': 0,
            'framework_busy': false,
            'extensions_busy': [],
          },
          'extensions': {},
          'screenshot_png_b64': screenshots[index],
        },
      }));
    },
  );
  developer.registerExtension('ext.leonard.core.wait', (_, __) async {
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'ok': true,
      'value': {},
    }));
  });
  developer.registerExtension('ext.leonard.core.done', (_, __) async {
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'ok': true,
      'value': {},
    }));
  });

  final developer.ServiceProtocolInfo serviceInfo =
      await developer.Service.getInfo();
  final Uri? vmUri = serviceInfo.serverWebSocketUri;
  if (vmUri == null) {
    stderr.writeln('VM service did not expose a WebSocket URI');
    exitCode = 1;
    return;
  }
  stdout.writeln(jsonEncode({
    'event': 'vm_service_ready',
    'ws_uri': vmUri.toString(),
  }));
  await stdout.flush();
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
''';
}

String _findPackageRoot() {
  Directory directory = Directory.current;
  for (var i = 0; i < 8; i++) {
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
