import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

const Duration _bootDeadline = Duration(minutes: 6);
const Duration _toolsDeadline = Duration(seconds: 30);
const String _targetWorkspaceEnvironment =
    'LEONARD_LIVE_SMOKE_TARGET_WORKSPACE';

Future<void> main(List<String> arguments) async {
  try {
    final LiveMacosSmokeConfiguration configuration =
        parseLiveMacosSmokeConfiguration(arguments);
    final Map<String, Object> receipt = await _runSmoke(configuration);
    stdout.writeln(
      jsonEncode(<String, Object>{'event': 'LIVE_SMOKE_PASS', ...receipt}),
    );
    exitCode = 0;
  } on Object catch (error) {
    stderr.writeln(
      jsonEncode(<String, Object>{
        'event': 'LIVE_SMOKE_FAIL',
        'error': error.toString(),
      }),
    );
    exitCode = 1;
  }
}

/// Parses command-line and workspace inputs for the live macOS smoke.
///
/// Explicit non-blank command-line configuration takes precedence over the
/// injected environment, then the source workspace.
LiveMacosSmokeConfiguration parseLiveMacosSmokeConfiguration(
  List<String> arguments, {
  Map<String, String>? environment,
  String? sourceWorkspace,
}) {
  final ArgParser parser = ArgParser()
    ..addOption(
      'target-workspace',
      help: 'Workspace whose normal LeonardBinding sample app is booted.',
    )
    ..addOption(
      'target',
      defaultsTo: p.join('lib', 'main.dart'),
      help: 'Entrypoint relative to the sample app directory.',
    );

  final ArgResults results = parser.parse(arguments);
  if (results.rest.isNotEmpty) {
    throw FormatException(
      'unexpected positional arguments: ${results.rest.join(' ')}',
    );
  }

  final String resolvedSourceWorkspace =
      sourceWorkspace ?? _findSourceWorkspace();
  final String? workspaceOption = results['target-workspace'] as String?;
  final String? workspaceEnvironment =
      (environment ?? Platform.environment)[_targetWorkspaceEnvironment];
  final String targetWorkspace = p.normalize(
    p.absolute(
      workspaceOption?.trim().isNotEmpty == true
          ? workspaceOption!
          : workspaceEnvironment?.trim().isNotEmpty == true
          ? workspaceEnvironment!
          : resolvedSourceWorkspace,
    ),
  );

  return LiveMacosSmokeConfiguration(
    sourceWorkspace: resolvedSourceWorkspace,
    targetWorkspace: targetWorkspace,
    target: results['target'] as String,
  );
}

String _findSourceWorkspace() {
  Directory directory = File.fromUri(Platform.script).parent;
  while (true) {
    final File driver = File(
      p.join(
        directory.path,
        'packages',
        'leonard_cli',
        'bin',
        'leonard_drive.dart',
      ),
    );
    final File pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (driver.existsSync() && pubspec.existsSync()) {
      return p.normalize(directory.absolute.path);
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError(
    'cannot locate the workspace containing '
    'packages/leonard_cli/bin/leonard_drive.dart',
  );
}

Future<Map<String, Object>> _runSmoke(
  LiveMacosSmokeConfiguration configuration,
) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('live smoke requires a macOS host');
  }

  final String driveBin = p.join(
    configuration.sourceWorkspace,
    'packages',
    'leonard_cli',
    'bin',
    'leonard_drive.dart',
  );
  final String driverWorkingDirectory = p.dirname(p.dirname(driveBin));
  final String sampleApp = p.join(
    configuration.targetWorkspace,
    'packages',
    'leonard_flutter',
    'example',
    'sample_app',
  );
  if (!File(driveBin).existsSync()) {
    throw StateError('leonard_drive.dart not found at $driveBin');
  }
  if (!Directory(sampleApp).existsSync()) {
    throw StateError('sample app not found at $sampleApp');
  }

  final Directory receipts = await Directory.systemTemp.createTemp(
    'leonard_live_macos_smoke_',
  );
  final String uriFile = p.join(receipts.path, 'vm-service.uri');
  final String pidFile = p.join(receipts.path, 'up.pid');
  final String screenshotFile = p.join(receipts.path, 'screenshot.png');

  Process? up;
  Future<void>? stdoutDone;
  Future<void>? stderrDone;
  Object? primaryFailure;
  StackTrace? primaryStack;
  Map<String, Object>? receipt;

  try {
    final List<String> launchStdout = <String>[];
    final List<String> launchStderr = <String>[];
    final Completer<Uri> ready = Completer<Uri>();

    up = await Process.start(Platform.resolvedExecutable, <String>[
      'run',
      driveBin,
      'up',
      '--runner',
      'flutter',
      '-d',
      'macos',
      '-t',
      configuration.target,
      '--timeout',
      '300',
      '--uri-file',
      uriFile,
      '--pid-file',
      pidFile,
    ], workingDirectory: sampleApp);

    stdoutDone = up.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((String line) {
          launchStdout.add(line);
          if (ready.isCompleted) return;

          Object? decoded;
          try {
            decoded = jsonDecode(line);
          } on FormatException {
            return;
          }
          if (decoded is! Map || decoded['event'] != 'vm_service_ready') {
            return;
          }
          final Object? rawUri = decoded['ws_uri'];
          final Uri? uri = rawUri is String ? Uri.tryParse(rawUri) : null;
          if (!isValidVmServiceUri(uri)) {
            ready.completeError(
              StateError(
                _launchFailure(
                  'vm_service_ready carried an invalid ws_uri: $rawUri',
                  launchStdout,
                  launchStderr,
                ),
              ),
            );
            return;
          }
          ready.complete(uri);
        });
    stderrDone = up.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(launchStderr.add);

    final Uri vmServiceUri = await _awaitVmService(
      up: up,
      ready: ready.future,
      stdoutDone: stdoutDone,
      stderrDone: stderrDone,
      launchStdout: launchStdout,
      launchStderr: launchStderr,
    );

    await _waitForRouter(
      driveBin: driveBin,
      driverWorkingDirectory: driverWorkingDirectory,
      vmServiceUri: vmServiceUri,
    );

    final Map<String, dynamic> navigation = await _runDriverJson(
      driveBin: driveBin,
      driverWorkingDirectory: driverWorkingDirectory,
      arguments: <String>[
        'invoke',
        '--vm-uri',
        vmServiceUri.toString(),
        '--tool',
        'router.navigate',
        '--args',
        jsonEncode(<String, String>{'route_name': 'g-debounced-search'}),
      ],
      timeout: const Duration(minutes: 1),
    );
    final Map<String, dynamic> navigationResult = requireMap(
      navigation['result'],
      'router.navigate result',
    );
    if (navigationResult['ok'] != true) {
      throw StateError(
        'router.navigate did not return ok == true: $navigation',
      );
    }

    final Map<String, dynamic> observationEnvelope = await _runDriverJson(
      driveBin: driveBin,
      driverWorkingDirectory: driverWorkingDirectory,
      arguments: <String>['observe', '--vm-uri', vmServiceUri.toString()],
      timeout: const Duration(minutes: 1),
    );
    final Map<String, dynamic> observation = requireMap(
      observationEnvelope['observation'],
      'observation',
    );
    const String expectedLabel = 'Debounced search';
    if (!containsExactLabel(observation['core'], expectedLabel)) {
      throw StateError(
        'observation.core contains no exact label "$expectedLabel": '
        '${jsonEncode(observation['core'])}',
      );
    }

    final Map<String, dynamic> screenshot = await _runDriverJson(
      driveBin: driveBin,
      driverWorkingDirectory: driverWorkingDirectory,
      arguments: <String>[
        'screenshot',
        '--vm-uri',
        vmServiceUri.toString(),
        '--out',
        screenshotFile,
      ],
      timeout: const Duration(minutes: 1),
    );
    final Uint8List pngBytes = await File(screenshotFile).readAsBytes();
    validatePngSignature(pngBytes);
    if (pngBytes.length <= 1024) {
      throw StateError(
        'screenshot is trivially small: ${pngBytes.length} bytes',
      );
    }

    final image.Image? decoded = image.decodePng(pngBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw StateError('screenshot did not decode to positive dimensions');
    }
    final num reportedWidth = requireNumber(
      screenshot['width_px'],
      'screenshot width_px',
    );
    final num reportedHeight = requireNumber(
      screenshot['height_px'],
      'screenshot height_px',
    );
    if (decoded.width != reportedWidth || decoded.height != reportedHeight) {
      throw StateError(
        'decoded screenshot dimensions ${decoded.width}x${decoded.height} '
        'do not match reported ${reportedWidth}x$reportedHeight',
      );
    }

    receipt = <String, Object>{
      'uri_scheme': vmServiceUri.scheme,
      'observed_label': expectedLabel,
      'png_bytes': pngBytes.length,
      'width_px': decoded.width,
      'height_px': decoded.height,
    };
  } on Object catch (error, stack) {
    primaryFailure = error;
    primaryStack = stack;
  } finally {
    Object? cleanupFailure;
    StackTrace? cleanupStack;
    try {
      if (up != null) {
        await _tearDownHeldApp(
          up: up,
          driveBin: driveBin,
          driverWorkingDirectory: driverWorkingDirectory,
          pidFile: pidFile,
          stdoutDone: stdoutDone,
          stderrDone: stderrDone,
        );
      }
    } on Object catch (error, stack) {
      cleanupFailure = error;
      cleanupStack = stack;
    }
    try {
      await receipts.delete(recursive: true);
    } on Object catch (error, stack) {
      cleanupFailure ??= error;
      cleanupStack ??= stack;
    }

    if (cleanupFailure != null) {
      if (primaryFailure != null) {
        primaryFailure = StateError(
          '$primaryFailure\ncleanup also failed: $cleanupFailure',
        );
      } else {
        primaryFailure = cleanupFailure;
        primaryStack = cleanupStack;
      }
    }
  }

  if (primaryFailure != null) {
    Error.throwWithStackTrace(
      primaryFailure,
      primaryStack ?? StackTrace.current,
    );
  }
  return receipt!;
}

Future<Uri> _awaitVmService({
  required Process up,
  required Future<Uri> ready,
  required Future<void> stdoutDone,
  required Future<void> stderrDone,
  required List<String> launchStdout,
  required List<String> launchStderr,
}) async {
  Future<Uri> failOnEarlyExit() async {
    final int code = await up.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    throw StateError(
      _launchFailure(
        'leonard_drive up exited before VM-service readiness (code $code)',
        launchStdout,
        launchStderr,
      ),
    );
  }

  final Completer<Uri> deadline = Completer<Uri>();
  final Timer deadlineTimer = Timer(
    _bootDeadline,
    () => deadline.completeError(
      TimeoutException(
        _launchFailure(
          'no valid vm_service_ready event within '
          '${_bootDeadline.inMinutes} minutes',
          launchStdout,
          launchStderr,
        ),
        _bootDeadline,
      ),
    ),
  );
  try {
    return await Future.any<Uri>(<Future<Uri>>[
      ready,
      failOnEarlyExit(),
      deadline.future,
    ]);
  } finally {
    deadlineTimer.cancel();
  }
}

/// Whether [uri] is an authority-bearing WebSocket VM-service URI.
bool isValidVmServiceUri(Uri? uri) =>
    uri != null &&
    (uri.isScheme('ws') || uri.isScheme('wss')) &&
    uri.hasAuthority &&
    uri.host.isNotEmpty;

String _launchFailure(
  String message,
  List<String> launchStdout,
  List<String> launchStderr,
) =>
    '$message\n'
    'launch stdout:\n${launchStdout.join('\n')}\n'
    'launch stderr:\n${launchStderr.join('\n')}';

Future<void> _waitForRouter({
  required String driveBin,
  required String driverWorkingDirectory,
  required Uri vmServiceUri,
}) async {
  final DateTime deadline = DateTime.now().add(_toolsDeadline);
  String lastAttempt = 'tools was not invoked';
  while (true) {
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw StateError(
        'router namespace was not registered within '
        '${_toolsDeadline.inSeconds} seconds; last attempt: $lastAttempt',
      );
    }

    try {
      final Map<String, dynamic> tools = await _runDriverJson(
        driveBin: driveBin,
        driverWorkingDirectory: driverWorkingDirectory,
        arguments: <String>['tools', '--vm-uri', vmServiceUri.toString()],
        timeout: remaining,
      );
      final Object? namespaces = tools['namespaces'];
      if (namespaces is List &&
          namespaces.any(
            (Object? entry) => entry is Map && entry['namespace'] == 'router',
          )) {
        return;
      }
      lastAttempt = jsonEncode(tools);
    } on Object catch (error) {
      lastAttempt = error.toString();
    }

    final Duration afterAttempt = deadline.difference(DateTime.now());
    if (afterAttempt <= Duration.zero) continue;
    await Future<void>.delayed(
      afterAttempt < const Duration(milliseconds: 500)
          ? afterAttempt
          : const Duration(milliseconds: 500),
    );
  }
}

Future<Map<String, dynamic>> _runDriverJson({
  required String driveBin,
  required String driverWorkingDirectory,
  required List<String> arguments,
  required Duration timeout,
}) async {
  final _CommandResult result = await _runDriver(
    driveBin: driveBin,
    driverWorkingDirectory: driverWorkingDirectory,
    arguments: arguments,
    timeout: timeout,
  );
  final String command = arguments.first;
  if (result.exitCode != 0) {
    throw StateError(
      '$command exited ${result.exitCode}\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(result.stdout.trim());
  } on FormatException catch (error) {
    throw StateError(
      '$command emitted invalid JSON: $error\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
  return requireMap(decoded, '$command output');
}

Future<_CommandResult> _runDriver({
  required String driveBin,
  required String driverWorkingDirectory,
  required List<String> arguments,
  required Duration timeout,
}) async {
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', driveBin, ...arguments],
    workingDirectory: driverWorkingDirectory,
  );
  final Future<String> stdoutText = process.stdout
      .transform(utf8.decoder)
      .join();
  final Future<String> stderrText = process.stderr
      .transform(utf8.decoder)
      .join();

  int commandExitCode;
  try {
    commandExitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 5));
    final String capturedStdout = await stdoutText;
    final String capturedStderr = await stderrText;
    throw StateError(
      '${arguments.first} timed out after $timeout\n'
      'stdout:\n$capturedStdout\n'
      'stderr:\n$capturedStderr',
    );
  }

  return _CommandResult(
    exitCode: commandExitCode,
    stdout: await stdoutText,
    stderr: await stderrText,
  );
}

Future<void> _tearDownHeldApp({
  required Process up,
  required String driveBin,
  required String driverWorkingDirectory,
  required String pidFile,
  required Future<void>? stdoutDone,
  required Future<void>? stderrDone,
}) async {
  try {
    await _runDriver(
      driveBin: driveBin,
      driverWorkingDirectory: driverWorkingDirectory,
      arguments: <String>['down', '--pid-file', pidFile],
      timeout: const Duration(seconds: 10),
    );
  } on Object {
    // Escalation below targets only the held `up` process.
  }

  try {
    await up.exitCode.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    up.kill(ProcessSignal.sigterm);
    try {
      await up.exitCode.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      up.kill(ProcessSignal.sigkill);
      await up.exitCode.timeout(const Duration(seconds: 5));
    }
  }

  await Future.wait(<Future<void>>[
    if (stdoutDone != null) stdoutDone,
    if (stderrDone != null) stderrDone,
  ]).timeout(const Duration(seconds: 5));
}

/// Returns [value] as a JSON object or throws a descriptive [StateError].
Map<String, dynamic> requireMap(Object? value, String description) {
  if (value is! Map) {
    throw StateError('$description must be a JSON object, got $value');
  }
  if (value.keys.any((Object? key) => key is! String)) {
    throw StateError('$description has non-string keys: $value');
  }
  return value.cast<String, dynamic>();
}

/// Returns [value] as a JSON number or throws a descriptive [StateError].
num requireNumber(Object? value, String description) {
  if (value is! num) {
    throw StateError('$description must be numeric, got $value');
  }
  return value;
}

/// Recursively searches JSON-like [value] for an exact `label` value.
bool containsExactLabel(Object? value, String expectedLabel) {
  if (value is Map) {
    if (value['label'] == expectedLabel) return true;
    for (final Object? child in value.values) {
      if (containsExactLabel(child, expectedLabel)) return true;
    }
  } else if (value is List) {
    for (final Object? child in value) {
      if (containsExactLabel(child, expectedLabel)) return true;
    }
  }
  return false;
}

/// Throws when [bytes] does not begin with the eight-byte PNG signature.
void validatePngSignature(List<int> bytes) {
  const List<int> signature = <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];
  if (bytes.length < signature.length) {
    throw StateError('screenshot is shorter than the PNG signature');
  }
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      throw StateError('screenshot does not begin with the PNG signature');
    }
  }
}

/// Resolved paths and entrypoint used by the live macOS smoke.
final class LiveMacosSmokeConfiguration {
  const LiveMacosSmokeConfiguration({
    required this.sourceWorkspace,
    required this.targetWorkspace,
    required this.target,
  });

  final String sourceWorkspace;
  final String targetWorkspace;
  final String target;
}

final class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
