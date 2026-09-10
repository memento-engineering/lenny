import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart' show kDefaultAgentsMd;
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

import 'support/fake_e2e_runtime.dart';

const String _app = '/app';
const String _device = 'wired-ios';

String _devices({bool wireless = false, bool two = false}) =>
    jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'id': _device,
        'name': 'iPad',
        'targetPlatform': 'ios',
        'connectionInterface': wireless ? 'wireless' : 'attached',
        'isSupported': true,
      },
      if (two)
        <String, Object?>{
          'id': 'second-ios',
          'name': 'Second iPad',
          'targetPlatform': 'ios',
          'connectionInterface': 'attached',
          'isSupported': true,
        },
    ]);

String _trajectory({
  String model = 'claude',
  String outcome = 'done',
  List<bool> actionResults = const <bool>[true, true],
  String route = 'home',
  String tool = 'core.done',
  String label = 'Dark Theme',
  List<String> state = const <String>['on'],
  bool unknown = false,
}) {
  final List<Map<String, Object?>> records = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'header',
      'goal': 'goal',
      'agents_md_hash': 'hash',
      'build_identifier': 'build',
      'model_identifier': model,
      'harness_version': '0.2.0',
      'extensions': <Object?>[],
      'config': <String, Object?>{},
    },
    for (var index = 0; index < actionResults.length; index++)
      <String, Object?>{
        'type': 'turn',
        'index': index,
        'observation': <String, Object?>{
          'core': <String, Object?>{
            'routeStack': <String>[route],
            'nodes': <String, Object?>{
              '1': <String, Object?>{'label': label, 'state': state},
            },
          },
          'extensions': <String, Object?>{},
          'stability': <String, Object?>{},
        },
        'stability': <String, Object?>{},
        'proposed_action': <String, Object?>{
          'tool': index == actionResults.length - 1 ? tool : 'core.tap',
          'args': <String, Object?>{'target': 'button'},
        },
        'validation': <String, Object?>{'ok': true},
        'executed_action': <String, Object?>{
          'tool': index == actionResults.length - 1 ? tool : 'core.tap',
          'args': <String, Object?>{'target': 'button'},
          'result': <String, Object?>{'ok': actionResults[index]},
        },
        'diff': <String, Object?>{},
        'model_metadata': <String, Object?>{},
        'provider_request_id': 'request-$index',
      },
    if (unknown) <String, Object?>{'type': 'future_record'},
    <String, Object?>{
      'type': 'footer',
      'outcome': outcome,
      'total_turns': actionResults.length,
      'total_duration_ms': 1250,
    },
  ];
  return records.map(jsonEncode).join('\n');
}

FakeE2eRuntime _runtime({
  String? devices,
  Map<String, String>? environment,
  String trajectory = '',
  int driverStatus = 0,
  FakeE2eChildProcess? child,
}) {
  late FakeE2eRuntime runtime;
  runtime = FakeE2eRuntime(
    environment: environment ?? <String, String>{'ANTHROPIC_API_KEY': 'key'},
    files: <String, String>{'$_app/pubspec.yaml': ''},
    directories: <String>{_app, '$_app/ios'},
    processHandler:
        (
          String executable,
          List<String> arguments,
          String? workingDirectory,
        ) async {
          if (executable == 'flutter' && arguments.first == 'devices') {
            return E2eProcessResult(exitCode: 0, stdout: devices ?? _devices());
          }
          if (executable == 'pkill') {
            return const E2eProcessResult(exitCode: 1);
          }
          final int output = arguments.indexOf('--output');
          if (output >= 0 && trajectory.isNotEmpty) {
            runtime.fileValues[arguments[output + 1]] = trajectory;
          }
          return E2eProcessResult(
            exitCode: driverStatus,
            stdout: 'PASS from child process',
          );
        },
    startHandler:
        (
          String executable,
          List<String> arguments,
          String workingDirectory,
          String logPath,
        ) async =>
            child ??
            FakeE2eChildProcess(
              output: const <String>[
                'A Dart VM Service is available at: '
                    'http://127.0.0.1:8181/token/',
              ],
            ),
  );
  return runtime;
}

E2eSessionRequest _request({
  E2eModel model = E2eModel.claude,
  String? modelId,
  String? device,
  E2eObservationExpectation expectation = const E2eObservationExpectation(
    route: 'home',
  ),
}) => E2eSessionRequest(
  goal: 'reach the target',
  appDir: _app,
  model: model,
  modelId: modelId,
  device: device,
  expectation: expectation,
);

E2eRunReceipt _receipt(String path, {int status = 0}) => E2eRunReceipt(
  trajectoryPath: path,
  driverExitStatus: status,
  stdout: 'PASS',
  stderr: '',
);

void main() {
  group('preflight', () {
    test('selects the sole eligible wired iOS device', () async {
      final E2ePreflight result = await E2eService(
        _runtime(),
      ).preflight(_request());
      expect(result.device.id, _device);
    });

    test('rejects a requested wireless device', () async {
      final E2eService service = E2eService(
        _runtime(devices: _devices(wireless: true)),
      );
      await expectLater(
        service.preflight(_request(device: _device)),
        throwsA(
          isA<E2ePhaseFailure>().having(
            (E2ePhaseFailure failure) => failure.code,
            'code',
            E2eFailureCode.wirelessDevice,
          ),
        ),
      );
    });

    test('requires exactly one eligible device without an id', () async {
      final E2eService service = E2eService(
        _runtime(devices: _devices(two: true)),
      );
      await expectLater(
        service.preflight(_request()),
        throwsA(
          isA<E2ePhaseFailure>().having(
            (E2ePhaseFailure failure) => failure.code,
            'code',
            E2eFailureCode.deviceSelection,
          ),
        ),
      );
    });

    test('rejects a relative or incomplete app directory', () async {
      for (final String appDir in <String>['relative/app', '/missing']) {
        final E2eSessionRequest request = E2eSessionRequest(
          goal: 'goal',
          appDir: appDir,
        );
        await expectLater(
          E2eService(_runtime()).preflight(request),
          throwsA(
            isA<E2ePhaseFailure>().having(
              (E2ePhaseFailure failure) => failure.code,
              'code',
              E2eFailureCode.appDirectory,
            ),
          ),
        );
      }
    });

    for (final ({E2eModel model, String variable}) entry
        in <({E2eModel model, String variable})>[
          (model: E2eModel.claude, variable: 'ANTHROPIC_API_KEY'),
          (model: E2eModel.openai, variable: 'OPENAI_API_KEY'),
          (model: E2eModel.qwenMlx, variable: 'SWIFT_INFER_ENDPOINT'),
        ]) {
      test(
        '${entry.model.cliName} refuses missing ${entry.variable}',
        () async {
          final E2eService service = E2eService(
            _runtime(environment: <String, String>{}),
          );
          await expectLater(
            service.preflight(_request(model: entry.model)),
            throwsA(
              isA<E2ePhaseFailure>().having(
                (E2ePhaseFailure failure) => failure.code,
                'code',
                E2eFailureCode.missingEnvironment,
              ),
            ),
          );
        },
      );
    }

    test('qwen resolves and verifies the requested catalog model', () async {
      final FakeE2eRuntime runtime =
          _runtime(
              environment: <String, String>{
                'SWIFT_INFER_ENDPOINT': 'http://gateway/base/',
                'SWIFT_INFER_AGENT_TOKEN': 'token',
                'SWIFT_INFER_MODEL': 'environment-model',
              },
            )
            ..httpResponse = const E2eHttpResponse(
              statusCode: 200,
              body: '{"data":[{"id":"requested-model"}]}',
            );
      final E2ePreflight cleared = await E2eService(runtime).preflight(
        _request(model: E2eModel.qwenMlx, modelId: 'requested-model'),
      );
      expect(cleared.modelId, 'requested-model');
      expect(runtime.getCalls.single.path, '/base/v1/models');
    });

    test('qwen resolves environment then default model ids', () async {
      for (final ({String? environmentModel, String expected}) entry
          in <({String? environmentModel, String expected})>[
            (
              environmentModel: 'environment-model',
              expected: 'environment-model',
            ),
            (environmentModel: null, expected: kDefaultQwenModelId),
          ]) {
        final Map<String, String> environment = <String, String>{
          'SWIFT_INFER_ENDPOINT': 'http://gateway',
          'SWIFT_INFER_AGENT_TOKEN': 'token',
          if (entry.environmentModel != null)
            'SWIFT_INFER_MODEL': entry.environmentModel!,
        };
        final FakeE2eRuntime runtime = _runtime(environment: environment)
          ..httpResponse = E2eHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{'id': entry.expected},
              ],
            }),
          );
        final E2ePreflight cleared = await E2eService(
          runtime,
        ).preflight(_request(model: E2eModel.qwenMlx));
        expect(cleared.modelId, entry.expected);
      }
    });

    test('qwen refuses a missing token and an unserved model', () async {
      final E2eService missingToken = E2eService(
        _runtime(
          environment: <String, String>{
            'SWIFT_INFER_ENDPOINT': 'http://gateway',
          },
        ),
      );
      await expectLater(
        missingToken.preflight(_request(model: E2eModel.qwenMlx)),
        throwsA(
          isA<E2ePhaseFailure>().having(
            (E2ePhaseFailure failure) => failure.code,
            'code',
            E2eFailureCode.missingEnvironment,
          ),
        ),
      );

      final FakeE2eRuntime runtime = _runtime(
        environment: <String, String>{
          'SWIFT_INFER_ENDPOINT': 'http://gateway',
          'SWIFT_INFER_AGENT_TOKEN': 'token',
        },
      );
      await expectLater(
        E2eService(
          runtime,
        ).preflight(_request(model: E2eModel.qwenMlx, modelId: 'not-served')),
        throwsA(
          isA<E2ePhaseFailure>().having(
            (E2ePhaseFailure failure) => failure.code,
            'code',
            E2eFailureCode.modelCatalog,
          ),
        ),
      );
    });
  });

  test(
    'launch uses argv-based stale cleanup and tears down its lease',
    () async {
      final FakeE2eChildProcess child = FakeE2eChildProcess(
        output: const <String>[
          'The Dart VM Service is listening on http://127.0.0.1:9000/abc/',
        ],
      );
      final FakeE2eRuntime runtime = _runtime(child: child);
      final E2eService service = E2eService(runtime);
      final E2ePreflight cleared = await service.preflight(_request());
      final E2eLaunchHandle handle = await service.launch(_request(), cleared);
      expect(runtime.processCalls[1].arguments, <String>[
        '-f',
        'run -d $_device',
      ]);
      expect(runtime.processCalls[2].arguments, <String>[
        '-f',
        'iproxy.*$_device',
      ]);
      expect(runtime.startCalls.single.arguments, <String>[
        'run',
        '-d',
        _device,
        '--no-devtools',
      ]);
      expect(handle.vmUri.toString(), 'ws://127.0.0.1:9000/abc/ws');
      await service.teardown(handle);
      expect(child.killCount, 1);
    },
  );

  test('run preserves nonzero driver status and exact Leonard argv', () async {
    final FakeE2eRuntime runtime = _runtime(driverStatus: 17);
    final E2eRunReceipt receipt = await E2eService(runtime).run(
      _request(modelId: 'exact-model'),
      vmUri: Uri.parse('ws://vm/ws'),
      runDir: '/run',
      resolvedModelId: 'exact-model',
    );
    expect(receipt.driverExitStatus, 17);
    expect(receipt.trajectoryPath, '/run/trajectory.jsonl');
    final ProcessCall call = runtime.processCalls.single;
    expect(call.executable, 'dart');
    expect(call.arguments, <String>[
      'run',
      'leonard_cli',
      '--vm-uri',
      'ws://vm/ws',
      '--goal',
      'reach the target',
      '--extensions',
      'router,riverpod,dio',
      '--model',
      'claude',
      '--policy',
      'action-relative',
      '--output',
      '/run/trajectory.jsonl',
      '--probe-artifact',
      '/run/probe.json',
      '--agents-md',
      '/run/AGENTS.md',
      '--model-id',
      'exact-model',
    ]);
    expect(runtime.fileValues['/run/AGENTS.md'], kDefaultAgentsMd);
  });

  group('typed inspection', () {
    Future<E2eVerdict> inspect(
      String contents, {
      E2eSessionRequest? request,
      int status = 0,
    }) {
      final FakeE2eRuntime runtime = _runtime();
      runtime.fileValues['/trajectory'] = contents;
      return E2eService(runtime).inspect(
        request ?? _request(),
        _receipt('/trajectory', status: status),
        deviceId: _device,
      );
    }

    test('passes typed footer, action, model, and route evidence', () async {
      final E2eVerdict verdict = await inspect(_trajectory());
      expect(verdict.status, E2eVerdictStatus.pass);
      expect(verdict.turns, 2);
      expect(verdict.durationMilliseconds, 1250);
      expect(verdict.providerRequestId, 'request-1');
      expect(verdict.expectationEvidence['matched'], true);
    });

    test('accepts one recovered action failure', () async {
      final E2eVerdict verdict = await inspect(
        _trajectory(actionResults: const <bool>[false, true]),
      );
      expect(verdict.status, E2eVerdictStatus.pass);
      expect(verdict.actionFailures, 1);
    });

    test('reports malformed and missing trajectories', () async {
      final FakeE2eRuntime missing = _runtime();
      expect(
        (await E2eService(missing).inspect(
          _request(),
          _receipt('/missing'),
          deviceId: _device,
        )).failureCodes,
        <E2eFailureCode>[E2eFailureCode.trajectoryMissing],
      );
      expect((await inspect('{not json')).failureCodes, <E2eFailureCode>[
        E2eFailureCode.malformedTrajectory,
      ]);
    });

    test(
      'classifies model, outcome, action, loop, and evidence failures',
      () async {
        expect(
          (await inspect(_trajectory(model: 'openai'))).failureCodes,
          contains(E2eFailureCode.modelMismatch),
        );
        expect(
          (await inspect(
            _trajectory(outcome: 'budget_exhausted'),
          )).failureCodes,
          contains(E2eFailureCode.outcomeNotDone),
        );
        expect(
          (await inspect(
            _trajectory(actionResults: const <bool>[false, false]),
          )).failureCodes,
          contains(E2eFailureCode.actionFailure),
        );
        expect(
          (await inspect(
            _trajectory(
              actionResults: const <bool>[true, true, true],
              tool: 'core.tap',
            ),
          )).failureCodes,
          contains(E2eFailureCode.terminalLoop),
        );
        expect(
          (await inspect(_trajectory(route: 'login'))).failureCodes,
          contains(E2eFailureCode.expectationUnmet),
        );
        expect(
          (await inspect(_trajectory(unknown: true))).failureCodes,
          contains(E2eFailureCode.trajectoryShape),
        );
      },
    );

    test('matches final semantics label and state', () async {
      final E2eVerdict verdict = await inspect(
        _trajectory(),
        request: _request(
          expectation: const E2eObservationExpectation(
            semanticsLabel: 'Dark Theme',
            semanticsState: 'on',
          ),
        ),
      );
      expect(verdict.passed, true);
    });
  });

  test('runSession ignores child PASS prose when typed footer fails', () async {
    final FakeE2eChildProcess child = FakeE2eChildProcess(
      output: const <String>[
        'The Dart VM Service is listening on http://127.0.0.1:8181/token/',
      ],
    );
    final E2eVerdict verdict = await E2eService(
      _runtime(
        child: child,
        driverStatus: 0,
        trajectory: _trajectory(outcome: 'harness_error'),
      ),
    ).runSession(_request());
    expect(verdict.status, E2eVerdictStatus.fail);
    expect(verdict.failureCodes, contains(E2eFailureCode.outcomeNotDone));
    expect(child.killCount, 1);
  });
}
