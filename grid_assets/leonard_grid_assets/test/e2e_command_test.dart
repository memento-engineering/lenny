import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

import 'support/fake_e2e_runtime.dart';

E2eVerdict _verdict({bool pass = true, String path = '/trajectory'}) =>
    E2eVerdict(
      status: pass ? E2eVerdictStatus.pass : E2eVerdictStatus.fail,
      failureCodes: pass
          ? const <E2eFailureCode>[]
          : const <E2eFailureCode>[E2eFailureCode.outcomeNotDone],
      model: E2eModel.claude,
      device: 'device',
      turns: 2,
      durationMilliseconds: 12,
      trajectoryPath: path,
      driverExitStatus: 9,
      providerRequestId: 'request',
      actionFailures: 0,
      expectationEvidence: const <String, Object?>{'matched': true},
    );

class _RecordingService extends E2eService {
  _RecordingService(FakeE2eRuntime super.runtime);

  final List<E2eSessionRequest> requests = <E2eSessionRequest>[];
  ({
    String appDir,
    E2eModel model,
    String? modelId,
    String? device,
    List<String> extensions,
    List<String> cliPrefix,
    List<E2eScenario> scenarios,
  })?
  suiteCall;
  E2eVerdict sessionVerdict = _verdict();

  @override
  Future<E2eVerdict> runSession(E2eSessionRequest request) async {
    requests.add(request);
    return sessionVerdict;
  }

  @override
  Future<E2eSuiteVerdict> runSampleSuite({
    required String appDir,
    E2eModel model = E2eModel.claude,
    String? modelId,
    String? device,
    List<String> extensions = const <String>['router', 'riverpod', 'dio'],
    List<String> cliPrefix = const <String>['dart', 'run', 'leonard_cli'],
    List<E2eScenario> scenarios = kLeonardSampleSuite,
  }) async {
    suiteCall = (
      appDir: appDir,
      model: model,
      modelId: modelId,
      device: device,
      extensions: List<String>.from(extensions),
      cliPrefix: List<String>.from(cliPrefix),
      scenarios: List<E2eScenario>.from(scenarios),
    );
    return E2eSuiteVerdict(
      status: E2eVerdictStatus.pass,
      model: model,
      scenarios: <E2eScenarioVerdict>[
        for (var index = 0; index < scenarios.length; index++)
          E2eScenarioVerdict(
            scenario: scenarios[index],
            verdict: _verdict(path: '/trajectory-$index'),
          ),
      ],
    );
  }
}

Future<int?> _run(
  _RecordingService service,
  List<String> arguments,
  StringBuffer out,
  StringBuffer err,
) =>
    (CommandRunner<int>('test', 'test')
          ..addCommand(E2eCommand(service: service, out: out, err: err)))
        .run(<String>['e2e', ...arguments]);

void main() {
  test('generic mode maps exact defaults and emits one JSON object', () async {
    final _RecordingService service = _RecordingService(FakeE2eRuntime());
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(
      await _run(
        service,
        <String>['--goal', 'open home', '--app-dir', '/app'],
        out,
        err,
      ),
      0,
    );
    final E2eSessionRequest request = service.requests.single;
    expect(request.goal, 'open home');
    expect(request.model, E2eModel.claude);
    expect(request.extensions, <String>['router', 'riverpod', 'dio']);
    expect(request.cliPrefix, <String>['dart', 'run', 'leonard_cli']);
    expect(err, isEmpty);
    expect(out.toString().trim().split('\n'), hasLength(1));
    expect(
      jsonDecode(out.toString()) as Map<String, dynamic>,
      containsPair('status', 'pass'),
    );
  });

  test(
    'generic mode maps all optional flags without service-side parsing',
    () async {
      final _RecordingService service = _RecordingService(FakeE2eRuntime());
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      expect(
        await _run(
          service,
          <String>[
            '--goal',
            'goal',
            '--app-dir',
            '/app',
            '--model',
            'qwen-mlx',
            '--model-id',
            'model',
            '--device',
            'ios',
            '--extensions',
            'router,dio',
            '--cli',
            "dart run 'bin/driver.dart'",
            '--done-reason-pattern',
            'reason',
            '--done-evidence-pattern',
            'evidence',
            '--expect-label',
            'Toggle',
            '--expect-state',
            'on',
          ],
          out,
          err,
        ),
        0,
      );
      final E2eSessionRequest request = service.requests.single;
      expect(request.model, E2eModel.qwenMlx);
      expect(request.modelId, 'model');
      expect(request.device, 'ios');
      expect(request.extensions, <String>['router', 'dio']);
      expect(request.cliPrefix, <String>['dart', 'run', 'bin/driver.dart']);
      expect(request.doneReasonPattern, 'reason');
      expect(request.doneEvidencePattern, 'evidence');
      expect(request.expectation.semanticsLabel, 'Toggle');
      expect(request.expectation.semanticsState, 'on');
    },
  );

  test('invalid mode combinations write usage to err and return 64', () async {
    for (final List<String> arguments in <List<String>>[
      <String>[],
      <String>['--goal', 'goal', '--sample-suite', '--app-dir', '/app'],
      <String>['--goal', 'goal', '--app-dir', 'relative'],
      <String>[
        '--goal',
        'goal',
        '--app-dir',
        '/app',
        '--expect-label',
        'Toggle',
      ],
    ]) {
      final _RecordingService service = _RecordingService(FakeE2eRuntime());
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      expect(await _run(service, arguments, out, err), 64);
      expect(out, isEmpty);
      expect(err.toString(), contains('Usage:'));
      expect(service.requests, isEmpty);
      expect(service.suiteCall, isNull);
    }
  });

  test('sample scenario outside suite mode refuses before service', () async {
    final _RecordingService service = _RecordingService(FakeE2eRuntime());
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();

    expect(
      await _run(
        service,
        const <String>[
          '--goal',
          'goal',
          '--app-dir',
          '/app',
          '--sample-scenario',
          'login',
        ],
        out,
        err,
      ),
      64,
    );
    expect(out, isEmpty);
    expect(
      err.toString(),
      contains('--sample-scenario requires --sample-suite'),
    );
    expect(service.requests, isEmpty);
    expect(service.suiteCall, isNull);
  });

  test('unknown sample scenario refuses before service', () async {
    final _RecordingService service = _RecordingService(FakeE2eRuntime());
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();

    expect(
      await _run(
        service,
        const <String>[
          '--sample-suite',
          '--sample-scenario',
          'unknown',
          '--app-dir',
          '/app',
        ],
        out,
        err,
      ),
      64,
    );
    expect(out, isEmpty);
    expect(
      err.toString(),
      contains(
        '--sample-scenario must be login, navigation, state_change, or scroll',
      ),
    );
    expect(service.requests, isEmpty);
    expect(service.suiteCall, isNull);
  });

  test(
    'sample suite resolves the corrected path and emits one report',
    () async {
      final FakeE2eRuntime runtime = FakeE2eRuntime(
        directories: <String>{'/repo/$kLeonardSampleAppDir'},
      );
      final _RecordingService service = _RecordingService(runtime);
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      expect(
        await _run(service, const <String>['--sample-suite'], out, err),
        0,
      );
      expect(service.suiteCall!.appDir, '/repo/$kLeonardSampleAppDir');
      expect(service.suiteCall!.model, E2eModel.claude);
      expect(service.suiteCall!.extensions, <String>[
        'router',
        'riverpod',
        'dio',
      ]);
      expect(
        service.suiteCall!.scenarios.map(
          (E2eScenario scenario) => scenario.name,
        ),
        <String>['login', 'navigation', 'state_change', 'scroll'],
      );
      final Map<String, dynamic> report =
          jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(report['status'], 'pass');
      expect(report['scenarios'] as List<dynamic>, hasLength(4));
      expect(out.toString().trim().split('\n'), hasLength(1));
      expect(err, isEmpty);
    },
  );

  test('sample scenario selects one matching scenario', () async {
    final _RecordingService service = _RecordingService(FakeE2eRuntime());
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();

    expect(
      await _run(
        service,
        const <String>[
          '--sample-suite',
          '--sample-scenario',
          'login',
          '--app-dir',
          '/app',
          '--model',
          'qwen-mlx',
        ],
        out,
        err,
      ),
      0,
    );
    expect(service.suiteCall!.model, E2eModel.qwenMlx);
    expect(
      service.suiteCall!.scenarios.map((E2eScenario scenario) => scenario.name),
      <String>['login'],
    );
    final Map<String, dynamic> report =
        jsonDecode(out.toString()) as Map<String, dynamic>;
    expect(report['scenarios'] as List<dynamic>, hasLength(1));
    expect(
      (report['scenarios'] as List<dynamic>).single,
      containsPair('scenario', 'login'),
    );
    expect(err, isEmpty);
  });

  test(
    'failed verdict returns one while preserving JSON-only stdout',
    () async {
      final _RecordingService service = _RecordingService(FakeE2eRuntime())
        ..sessionVerdict = _verdict(pass: false);
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      expect(
        await _run(
          service,
          const <String>['--goal', 'goal', '--app-dir', '/app'],
          out,
          err,
        ),
        1,
      );
      expect(
        (jsonDecode(out.toString()) as Map<String, dynamic>)['status'],
        'fail',
      );
      expect(err, isEmpty);
    },
  );
}
