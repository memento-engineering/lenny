import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

import 'support/fake_e2e_runtime.dart';

void main() {
  test('launch uninstalls the previous iOS app before relaunching', () async {
    final _RecordingSystemE2eRuntime runtime = _RecordingSystemE2eRuntime();
    final E2eLaunchHandle handle = await performE2eLaunch(
      runtime,
      E2eSessionRequest(goal: 'reach the target', appDir: '/app'),
      const E2ePreflight(
        device: FlutterDevice(
          id: 'wired-ios',
          name: 'iPad',
          targetPlatform: 'ios',
          connectionInterface: 'attached',
          isSupported: true,
        ),
        modelId: null,
      ),
    );

    expect(runtime.processCalls.last.executable, 'flutter');
    expect(runtime.processCalls.last.arguments, <String>[
      'install',
      '--uninstall-only',
      '-d',
      'wired-ios',
    ]);
    expect(runtime.processCalls.last.workingDirectory, '/app');
    expect(runtime.startCalls.single.arguments, <String>[
      'run',
      '-d',
      'wired-ios',
      '--no-devtools',
    ]);
    await handle.process.kill();
  });

  test('launch refuses when the previous iOS app cannot be removed', () async {
    final _RecordingSystemE2eRuntime runtime = _RecordingSystemE2eRuntime(
      uninstallExitCode: 9,
    );

    await expectLater(
      performE2eLaunch(
        runtime,
        E2eSessionRequest(goal: 'reach the target', appDir: '/app'),
        const E2ePreflight(
          device: FlutterDevice(
            id: 'wired-ios',
            name: 'iPad',
            targetPlatform: 'ios',
            connectionInterface: 'attached',
            isSupported: true,
          ),
          modelId: null,
        ),
      ),
      throwsA(
        isA<E2ePhaseFailure>().having(
          (E2ePhaseFailure failure) => failure.code,
          'code',
          E2eFailureCode.launch,
        ),
      ),
    );
    expect(runtime.startCalls, isEmpty);
  });
}

final class _RecordingSystemE2eRuntime extends SystemE2eRuntime {
  _RecordingSystemE2eRuntime({this.uninstallExitCode = 0});

  final int uninstallExitCode;
  final List<ProcessCall> processCalls = <ProcessCall>[];
  final List<StartCall> startCalls = <StartCall>[];

  @override
  Future<String> createRunDirectory() async => '/tmp/leonard-e2e-test';

  @override
  Future<E2eProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    processCalls.add(
      ProcessCall(executable, List<String>.from(arguments), workingDirectory),
    );
    return E2eProcessResult(
      exitCode: executable == 'flutter' ? uninstallExitCode : 1,
    );
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
    return FakeE2eChildProcess(
      output: const <String>[
        'The Dart VM Service is listening on http://127.0.0.1:8181/token/',
      ],
    );
  }
}
