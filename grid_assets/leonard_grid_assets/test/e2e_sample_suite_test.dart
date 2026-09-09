import 'dart:convert';

import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

import 'support/fake_e2e_runtime.dart';

String _scenarioTrajectory(int index) {
  final bool routeScenario = index < 2;
  final String route = index == 0 ? 'home' : 'settings';
  final String label = index == 2 ? 'Dark Theme' : 'Accept Terms';
  return <Map<String, Object?>>[
    <String, Object?>{
      'type': 'header',
      'goal': kLeonardSampleSuite[index].goal,
      'agents_md_hash': 'hash',
      'build_identifier': 'build',
      'model_identifier': 'claude',
      'harness_version': '0.2.0',
      'extensions': <Object?>[],
      'config': <String, Object?>{},
    },
    <String, Object?>{
      'type': 'turn',
      'index': 0,
      'observation': <String, Object?>{
        'core': <String, Object?>{
          'routeStack': routeScenario ? <String>[route] : <String>['settings'],
          'nodes': routeScenario
              ? <String, Object?>{}
              : <String, Object?>{
                  '1': <String, Object?>{
                    'label': label,
                    'state': <String>['on'],
                  },
                },
        },
      },
      'stability': <String, Object?>{},
      'proposed_action': <String, Object?>{
        'tool': 'core.done',
        'args': <String, Object?>{'reason': 'complete'},
      },
      'validation': <String, Object?>{'ok': true},
      'executed_action': <String, Object?>{
        'tool': 'core.done',
        'args': <String, Object?>{'reason': 'complete'},
        'result': <String, Object?>{'ok': true},
      },
      'diff': <String, Object?>{},
      'model_metadata': <String, Object?>{},
      'provider_request_id': 'request-$index',
    },
    <String, Object?>{
      'type': 'footer',
      'outcome': 'done',
      'total_turns': 1,
      'total_duration_ms': 100,
    },
  ].map(jsonEncode).join('\n');
}

void main() {
  test('the four scenarios compose sequential fresh sessions', () async {
    const String appDir = '/repo/$kLeonardSampleAppDir';
    final List<FakeE2eChildProcess> children = <FakeE2eChildProcess>[];
    final List<List<String>> driverArgv = <List<String>>[];
    late FakeE2eRuntime runtime;
    runtime = FakeE2eRuntime(
      environment: <String, String>{'ANTHROPIC_API_KEY': 'key'},
      files: <String, String>{'$appDir/pubspec.yaml': ''},
      directories: <String>{appDir, '$appDir/ios'},
      processHandler:
          (
            String executable,
            List<String> arguments,
            String? workingDirectory,
          ) async {
            if (executable == 'flutter' && arguments.first == 'devices') {
              return const E2eProcessResult(
                exitCode: 0,
                stdout:
                    '[{"id":"ios","name":"iPad",'
                    '"targetPlatform":"ios",'
                    '"connectionInterface":"attached",'
                    '"isSupported":true}]',
              );
            }
            if (executable == 'pkill') {
              return const E2eProcessResult(exitCode: 1);
            }
            driverArgv.add(List<String>.from(arguments));
            final int index = driverArgv.length - 1;
            final int output = arguments.indexOf('--output');
            runtime.fileValues[arguments[output + 1]] = _scenarioTrajectory(
              index,
            );
            expect(children[index].killCount, 0);
            return const E2eProcessResult(exitCode: 0);
          },
      startHandler:
          (
            String executable,
            List<String> arguments,
            String workingDirectory,
            String logPath,
          ) async {
            if (children.isNotEmpty) {
              expect(children.last.killCount, 1);
            }
            final FakeE2eChildProcess child = FakeE2eChildProcess(
              output: <String>[
                'The Dart VM Service is listening on '
                    'http://127.0.0.1:${8100 + children.length}/token/',
              ],
            );
            children.add(child);
            return child;
          },
    );

    final E2eSuiteVerdict suite = await E2eService(
      runtime,
    ).runSampleSuite(appDir: appDir, device: 'ios');

    expect(suite.status, E2eVerdictStatus.pass);
    expect(suite.scenarios, hasLength(4));
    expect(
      suite.scenarios.map((E2eScenarioVerdict result) => result.scenario.name),
      <String>['login', 'navigation', 'state_change', 'scroll'],
    );
    expect(children, hasLength(4));
    expect(
      children.every((FakeE2eChildProcess child) => child.killCount == 1),
      true,
    );
    expect(runtime.runDirectories.toSet(), hasLength(4));
    expect(
      suite.scenarios
          .map((E2eScenarioVerdict result) => result.verdict.trajectoryPath)
          .toSet(),
      hasLength(4),
    );

    for (var index = 0; index < driverArgv.length; index++) {
      final List<String> argv = driverArgv[index];
      expect(argv[argv.indexOf('--goal') + 1], kLeonardSampleSuite[index].goal);
      expect(
        argv[argv.indexOf('--done-reason-pattern') + 1],
        kLeonardSampleSuite[index].doneReasonPattern,
      );
      expect(
        argv[argv.indexOf('--done-evidence-pattern') + 1],
        kLeonardSampleSuite[index].doneEvidencePattern,
      );
      expect(argv.join(' '), contains('demo@example.com'));
      expect(argv.join(' '), contains('password'));
    }
  });

  test('suite retains all verdicts and fails when any session fails', () async {
    final _ScriptedService service = _ScriptedService(FakeE2eRuntime());
    final E2eSuiteVerdict suite = await performE2eSampleSuite(
      service,
      appDir: '/app',
      model: E2eModel.claude,
      extensions: const <String>['router', 'riverpod', 'dio'],
      cliPrefix: const <String>['dart', 'run', 'leonard_cli'],
    );
    expect(suite.status, E2eVerdictStatus.fail);
    expect(suite.scenarios, hasLength(4));
    expect(service.requests, hasLength(4));
  });
}

class _ScriptedService extends E2eService {
  _ScriptedService(super.runtime);

  final List<E2eSessionRequest> requests = <E2eSessionRequest>[];

  @override
  Future<E2eVerdict> runSession(E2eSessionRequest request) async {
    requests.add(request);
    final bool pass = requests.length != 2;
    return E2eVerdict(
      status: pass ? E2eVerdictStatus.pass : E2eVerdictStatus.fail,
      failureCodes: pass
          ? const <E2eFailureCode>[]
          : const <E2eFailureCode>[E2eFailureCode.expectationUnmet],
      model: request.model,
      device: request.device,
      turns: 1,
      durationMilliseconds: 1,
      trajectoryPath: '/trajectory-${requests.length}',
      driverExitStatus: 0,
      providerRequestId: null,
      actionFailures: 0,
      expectationEvidence: <String, Object?>{'matched': pass},
    );
  }
}
