/// UI-drivable Leonard E2E orchestration behind one injectable IO boundary.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'e2e_inspect.dart';
import 'e2e_launch.dart';
import 'e2e_preflight.dart';
import 'e2e_run.dart';
import 'e2e_sample_suite.dart';
import 'e2e_session.dart';

/// Completed process data.
class E2eProcessResult {
  /// Creates process result data.
  const E2eProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Child exit code.
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;
}

/// HTTP response data used by swift-infer model preflight.
class E2eHttpResponse {
  /// Creates response data.
  const E2eHttpResponse({required this.statusCode, required this.body});

  /// HTTP response status.
  final int statusCode;

  /// Response body.
  final String body;
}

/// Observable handle for a long-lived process.
abstract interface class E2eChildProcess {
  /// Merged stdout/stderr lines.
  Stream<String> get output;

  /// Exit status when the process terminates.
  Future<int> get exitCode;

  /// Idempotently terminates the process.
  Future<void> kill();
}

/// Every IO operation needed by [E2eService].
abstract interface class E2eRuntime {
  /// Current working directory used for suite-root discovery.
  String get currentDirectory;

  /// Reads one environment value.
  String? environment(String name);

  /// Current UTC time.
  DateTime now();

  /// Whether [path] names a regular file.
  Future<bool> fileExists(String path);

  /// Whether [path] names a directory.
  Future<bool> directoryExists(String path);

  /// Reads a UTF-8 text file.
  Future<String> readFile(String path);

  /// Creates a distinct artifact directory.
  Future<String> createRunDirectory();

  /// Runs one argv-based child process to completion.
  Future<E2eProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });

  /// Starts one long-lived process and captures its output at [logPath].
  Future<E2eChildProcess> startProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required String logPath,
  });

  /// Issues one HTTP GET.
  Future<E2eHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  });
}

/// Production `dart:io` and HTTP implementation of [E2eRuntime].
class SystemE2eRuntime implements E2eRuntime {
  /// Creates the system runtime.
  const SystemE2eRuntime();

  @override
  String get currentDirectory => Directory.current.path;

  @override
  String? environment(String name) => Platform.environment[name];

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<String> readFile(String path) => File(path).readAsString();

  @override
  Future<String> createRunDirectory() async =>
      (await Directory.systemTemp.createTemp('leonard-e2e-')).path;

  @override
  Future<E2eProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return E2eProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  @override
  Future<E2eChildProcess> startProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required String logPath,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return _SystemE2eChildProcess(process, File(logPath).openWrite());
  }

  @override
  Future<E2eHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final http.Response response = await http.get(uri, headers: headers);
    return E2eHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }
}

class _SystemE2eChildProcess implements E2eChildProcess {
  _SystemE2eChildProcess(this._process, IOSink log) : _log = log {
    void listen(Stream<List<int>> bytes) {
      bytes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (String line) {
              _log.writeln(line);
              _output.add(line);
            },
            onError: _output.addError,
            onDone: _streamDone,
          );
    }

    listen(_process.stdout);
    listen(_process.stderr);
  }

  final Process _process;
  final IOSink _log;
  final StreamController<String> _output = StreamController<String>();
  var _endedStreams = 0;
  var _killed = false;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  void _streamDone() {
    _endedStreams += 1;
    if (_endedStreams != 2) return;
    unawaited(
      _log.flush().whenComplete(() async {
        await _log.close();
        await _output.close();
      }),
    );
  }

  @override
  Future<void> kill() async {
    if (_killed) return;
    _killed = true;
    _process.kill(ProcessSignal.sigterm);
    await _process.exitCode;
  }
}

/// Reusable single-session and sample-suite E2E service.
class E2eService {
  /// Creates the service over one IO implementation.
  const E2eService(this.runtime);

  /// IO boundary shared by every phase.
  final E2eRuntime runtime;

  /// Runs deterministic device, app, and provider checks.
  Future<E2ePreflight> preflight(E2eSessionRequest request) =>
      performE2ePreflight(runtime, request);

  /// Launches a fresh Flutter process and waits for VM-service readiness.
  Future<E2eLaunchHandle> launch(
    E2eSessionRequest request,
    E2ePreflight preflight,
  ) => performE2eLaunch(runtime, request, preflight);

  /// Invokes the outer Leonard driver and retains its exit status as data.
  Future<E2eRunReceipt> run(
    E2eSessionRequest request, {
    required Uri vmUri,
    required String runDir,
    String? resolvedModelId,
  }) => performE2eRun(
    runtime,
    request,
    vmUri: vmUri,
    runDir: runDir,
    resolvedModelId: resolvedModelId,
  );

  /// Derives a structured verdict exclusively from typed trajectory records.
  Future<E2eVerdict> inspect(
    E2eSessionRequest request,
    E2eRunReceipt receipt, {
    required String deviceId,
  }) => inspectE2eTrajectory(runtime, request, receipt, deviceId: deviceId);

  /// Releases a live Flutter launch.
  Future<void> teardown(E2eLaunchHandle handle) => handle.process.kill();

  /// Runs all phases, always tearing down a launch before returning.
  Future<E2eVerdict> runSession(E2eSessionRequest request) async {
    final DateTime started = runtime.now();
    E2ePreflight? cleared;
    E2eLaunchHandle? handle;
    E2eRunReceipt? receipt;
    late E2eVerdict verdict;
    try {
      cleared = await preflight(request);
      handle = await launch(request, cleared);
      receipt = await run(
        request,
        vmUri: handle.vmUri,
        runDir: handle.runDir,
        resolvedModelId: cleared.modelId,
      );
      verdict = await inspect(request, receipt, deviceId: handle.deviceId);
    } on E2ePhaseFailure catch (failure) {
      verdict = E2eVerdict.failed(
        code: failure.code,
        model: request.model,
        device: handle?.deviceId ?? cleared?.device.id,
        durationMilliseconds: runtime.now().difference(started).inMilliseconds,
        trajectoryPath: receipt?.trajectoryPath ?? '',
        driverExitStatus: receipt?.driverExitStatus,
        evidence: <String, Object?>{'message': failure.message},
      );
    } on Object catch (error) {
      verdict = E2eVerdict.failed(
        code: receipt == null && handle != null
            ? E2eFailureCode.driverInvocation
            : E2eFailureCode.unexpected,
        model: request.model,
        device: handle?.deviceId ?? cleared?.device.id,
        durationMilliseconds: runtime.now().difference(started).inMilliseconds,
        trajectoryPath: receipt?.trajectoryPath ?? '',
        driverExitStatus: receipt?.driverExitStatus,
        evidence: <String, Object?>{'message': '$error'},
      );
    }
    if (handle != null) {
      try {
        await teardown(handle);
      } on Object catch (error) {
        verdict = E2eVerdict.failed(
          code: E2eFailureCode.launch,
          model: request.model,
          device: handle.deviceId,
          durationMilliseconds: runtime
              .now()
              .difference(started)
              .inMilliseconds,
          trajectoryPath: receipt?.trajectoryPath ?? '',
          driverExitStatus: receipt?.driverExitStatus,
          evidence: <String, Object?>{
            'message': 'e2e launch teardown failed: $error',
          },
        );
      }
    }
    return verdict;
  }

  /// Runs the four ordered sample scenarios through [runSession].
  Future<E2eSuiteVerdict> runSampleSuite({
    required String appDir,
    E2eModel model = E2eModel.claude,
    String? modelId,
    String? device,
    List<String> extensions = const <String>['router', 'riverpod', 'dio'],
    List<String> cliPrefix = const <String>['dart', 'run', 'leonard_cli'],
  }) => performE2eSampleSuite(
    this,
    appDir: appDir,
    model: model,
    modelId: modelId,
    device: device,
    extensions: extensions,
    cliPrefix: cliPrefix,
  );
}
