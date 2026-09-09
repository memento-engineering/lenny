import 'dart:async';

import 'package:leonard_grid_assets/leonard_grid_assets.dart';

typedef FakeProcessHandler =
    Future<E2eProcessResult> Function(
      String executable,
      List<String> arguments,
      String? workingDirectory,
    );

typedef FakeStartHandler =
    Future<E2eChildProcess> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
      String logPath,
    );

class ProcessCall {
  const ProcessCall(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class StartCall {
  const StartCall(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.logPath,
  );

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final String logPath;
}

class FakeE2eChildProcess implements E2eChildProcess {
  FakeE2eChildProcess({
    Iterable<String> output = const <String>[],
    int? exitedWith,
  }) : _output = Stream<String>.fromIterable(output) {
    if (exitedWith != null) _exit.complete(exitedWith);
  }

  final Stream<String> _output;
  final Completer<int> _exit = Completer<int>();
  var killCount = 0;

  @override
  Stream<String> get output => _output;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> kill() async {
    killCount += 1;
    if (!_exit.isCompleted) _exit.complete(-15);
  }
}

class FakeE2eRuntime implements E2eRuntime {
  FakeE2eRuntime({
    this.currentDirectory = '/repo/grid_assets/leonard_grid_assets',
    Map<String, String>? environment,
    Map<String, String>? files,
    Set<String>? directories,
    this.processHandler,
    this.startHandler,
    this.httpResponse = const E2eHttpResponse(
      statusCode: 200,
      body: '{"data":[]}',
    ),
  }) : environmentValues = environment ?? <String, String>{},
       fileValues = files ?? <String, String>{},
       directoryValues = directories ?? <String>{};

  @override
  final String currentDirectory;
  final Map<String, String> environmentValues;
  final Map<String, String> fileValues;
  final Set<String> directoryValues;
  FakeProcessHandler? processHandler;
  FakeStartHandler? startHandler;
  E2eHttpResponse httpResponse;
  final List<ProcessCall> processCalls = <ProcessCall>[];
  final List<StartCall> startCalls = <StartCall>[];
  final List<Uri> getCalls = <Uri>[];
  final List<String> runDirectories = <String>[];
  var _runIndex = 0;
  var clock = DateTime.utc(2026, 9, 7);

  @override
  String? environment(String name) => environmentValues[name];

  @override
  DateTime now() => clock;

  @override
  Future<bool> fileExists(String path) async => fileValues.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async =>
      directoryValues.contains(path);

  @override
  Future<String> readFile(String path) async => fileValues[path]!;

  @override
  Future<String> createRunDirectory() async {
    final String path = '/tmp/leonard-e2e-${_runIndex++}';
    runDirectories.add(path);
    directoryValues.add(path);
    return path;
  }

  @override
  Future<E2eProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    processCalls.add(
      ProcessCall(executable, List<String>.from(arguments), workingDirectory),
    );
    final FakeProcessHandler? handler = processHandler;
    if (handler != null) {
      return handler(executable, arguments, workingDirectory);
    }
    return const E2eProcessResult(exitCode: 0);
  }

  @override
  Future<E2eChildProcess> startProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required String logPath,
  }) async {
    startCalls.add(
      StartCall(
        executable,
        List<String>.from(arguments),
        workingDirectory,
        logPath,
      ),
    );
    final FakeStartHandler? handler = startHandler;
    if (handler != null) {
      return handler(executable, arguments, workingDirectory, logPath);
    }
    return FakeE2eChildProcess(
      output: const <String>[
        'The Dart VM Service is listening on http://127.0.0.1:8181/token/',
      ],
    );
  }

  @override
  Future<E2eHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    getCalls.add(uri);
    return httpResponse;
  }
}
