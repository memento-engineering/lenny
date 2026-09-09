import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

import 'support/fake_e2e_runtime.dart';

const String _app = '/app';
const Bead _bead = Bead(
  id: 'work',
  metadata: <String, dynamic>{
    kE2eGoalKey: 'goal',
    kE2eAppDirKey: _app,
    kE2eDeviceKey: 'ios',
    kE2eExpectRouteKey: 'home',
  },
);

FakeTreeContext _context([
  Map<String, Map<String, String>> results = const {},
]) => FakeTreeContext(
  values: <Type, Object>{
    Bead: _bead,
    SiblingView: SiblingView(results: results),
  },
);

String _trajectory(String outcome) => <Map<String, Object?>>[
  <String, Object?>{
    'type': 'header',
    'goal': 'goal',
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
        'routeStack': <String>['home'],
        'nodes': <String, Object?>{},
      },
    },
    'stability': <String, Object?>{},
    'proposed_action': <String, Object?>{
      'tool': 'core.done',
      'args': <String, Object?>{},
    },
    'validation': <String, Object?>{'ok': true},
    'executed_action': <String, Object?>{
      'tool': 'core.done',
      'args': <String, Object?>{},
      'result': <String, Object?>{'ok': true},
    },
    'diff': <String, Object?>{},
    'model_metadata': <String, Object?>{},
  },
  <String, Object?>{
    'type': 'footer',
    'outcome': outcome,
    'total_turns': 1,
    'total_duration_ms': 10,
  },
].map(jsonEncode).join('\n');

FakeE2eRuntime _runtime({int driverStatus = 0}) => FakeE2eRuntime(
  environment: <String, String>{'ANTHROPIC_API_KEY': 'key'},
  files: <String, String>{'$_app/pubspec.yaml': ''},
  directories: <String>{_app, '$_app/ios'},
  processHandler:
      (
        String executable,
        List<String> arguments,
        String? workingDirectory,
      ) async {
        if (executable == 'flutter') {
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
        return E2eProcessResult(exitCode: driverStatus);
      },
);

void main() {
  test('preflight publishes the selected device', () async {
    final StepOutcome outcome = await E2ePreflightCapability(
      E2eService(_runtime()),
    ).run(_context(), stepArgs('work/leonard-e2e/preflight'));
    expect(outcome, isA<Ok>());
    expect((outcome as Ok).payload, containsPair(kE2eDeviceResultKey, 'ios'));
  });

  test(
    'launch holds and releases a process while publishing readiness',
    () async {
      final FakeE2eChildProcess child = FakeE2eChildProcess(
        output: const <String>[
          'The Dart VM Service is listening on http://127.0.0.1:8181/token/',
        ],
      );
      final FakeE2eRuntime runtime = _runtime()
        ..startHandler =
            (
              String executable,
              List<String> arguments,
              String workingDirectory,
              String logPath,
            ) async => child;
      final E2eLaunchCapability capability = E2eLaunchCapability(
        E2eService(runtime),
      );
      final LeaseResolution<E2eLaunchHandle> resolution = await capability
          .acquire(
            _context(<String, Map<String, String>>{
              'work/leonard-e2e/preflight': <String, String>{
                kE2eDeviceResultKey: 'ios',
              },
            }),
            stepArgs('work/leonard-e2e/launch'),
          );
      expect(resolution, isA<LeaseBound<E2eLaunchHandle>>());
      final E2eLaunchHandle handle =
          (resolution as LeaseBound<E2eLaunchHandle>).handle;
      final StepOutcome outcome = await capability.dispatchOn(
        handle,
        _context(),
        stepArgs('work/leonard-e2e/launch'),
      );
      expect((outcome as Ok).payload, <String, String>{
        kE2eDeviceResultKey: 'ios',
        kE2eVmUriResultKey: 'ws://127.0.0.1:8181/token/ws',
        kE2eRunDirResultKey: '/tmp/leonard-e2e-0',
      });
      await capability.release(handle);
      expect(child.killCount, 1);
    },
  );

  test(
    'run publishes a nonzero driver status without failing the step',
    () async {
      final StepOutcome outcome =
          await E2eRunCapability(E2eService(_runtime(driverStatus: 23))).run(
            _context(<String, Map<String, String>>{
              'work/leonard-e2e/launch': <String, String>{
                kE2eVmUriResultKey: 'ws://vm/ws',
                kE2eRunDirResultKey: '/run',
              },
              'work/leonard-e2e/preflight': <String, String>{},
            }),
            stepArgs('work/leonard-e2e/run'),
          );
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, <String, String>{
        kE2eTrajectoryResultKey: '/run/trajectory.jsonl',
        kE2eDriverStatusResultKey: '23',
      });
    },
  );

  for (final String footer in <String>['done', 'harness_error']) {
    test('inspect alone maps typed $footer to the circuit verdict', () async {
      final FakeE2eRuntime runtime = _runtime();
      runtime.fileValues['/run/trajectory.jsonl'] = _trajectory(footer);
      final StepOutcome outcome =
          await E2eInspectCapability(E2eService(runtime)).run(
            _context(<String, Map<String, String>>{
              'work/leonard-e2e/launch': <String, String>{
                kE2eDeviceResultKey: 'ios',
              },
              'work/leonard-e2e/run': <String, String>{
                kE2eTrajectoryResultKey: '/run/trajectory.jsonl',
                kE2eDriverStatusResultKey: '9',
              },
            }),
            stepArgs('work/leonard-e2e/inspect'),
          );
      if (footer == 'done') {
        expect(outcome, isA<Ok>());
        final String json = (outcome as Ok).payload![kE2eVerdictJsonResultKey]!;
        expect(jsonDecode(json), containsPair('status', 'pass'));
      } else {
        expect(outcome, isA<Failed>());
        expect(
          jsonDecode((outcome as Failed).reason),
          containsPair('status', 'fail'),
        );
      }
    });
  }
}
