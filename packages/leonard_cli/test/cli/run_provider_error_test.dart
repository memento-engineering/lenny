import 'dart:convert';
import 'dart:io';

import 'package:leonard_acp/leonard_acp.dart' show AcpAgentSpec;
import 'package:leonard_agent/leonard_agent.dart'
    show DartanticModelProvider, ModelProvider, SwiftInferBackend;
import 'package:leonard_cli/src/cli_args.dart' show ModelTier;
import 'package:leonard_cli/src/provider_factory.dart';
import 'package:leonard_cli/src/run.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'TypeError from provider builder propagates without config footer',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-provider-error-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
      final File errorFile = File(p.join(temp.path, 'stderr.txt'));
      final IOSink errorSink = errorFile.openWrite();
      final TypeError programmingError = TypeError();

      try {
        await expectLater(
          runCli(
            _arguments(trajectory.path),
            stdin: stdin,
            stdout: stdout,
            stderr: errorSink,
            acpProviderBuilder: (AcpAgentSpec spec) =>
                Future<ModelProvider>.error(
                  programmingError,
                  StackTrace.current,
                ),
          ),
          throwsA(same(programmingError)),
        );
      } finally {
        await errorSink.close();
      }

      expect(await errorFile.readAsString(), isNot(contains('config_error')));
      expect(await trajectory.readAsString(), isNot(contains('config_error')));
    },
  );

  test('configuration failures return 1 with config footer', () async {
    final List<({String label, Object error})> cases =
        <({String label, Object error})>[
          (label: 'state', error: StateError('missing configuration')),
          (
            label: 'acp',
            error: AcpProviderConfigurationException(
              harnessLabel: 'codex-acp',
              operation: 'start',
              cause: Exception('could not start'),
            ),
          ),
        ];

    for (final ({String label, Object error}) testCase in cases) {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-provider-${testCase.label}-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
      final File errorFile = File(p.join(temp.path, 'stderr.txt'));
      final IOSink errorSink = errorFile.openWrite();

      late final int exitCode;
      try {
        exitCode = await runCli(
          _arguments(trajectory.path),
          stdin: stdin,
          stdout: stdout,
          stderr: errorSink,
          acpProviderBuilder: (AcpAgentSpec spec) =>
              Future<ModelProvider>.error(testCase.error, StackTrace.current),
        );
      } finally {
        await errorSink.close();
      }

      expect(exitCode, 1, reason: testCase.label);
      expect(
        await errorFile.readAsString(),
        contains('error: ${testCase.error}'),
        reason: testCase.label,
      );
      final List<String> lines = await trajectory.readAsLines();
      final Map<String, dynamic> footer =
          jsonDecode(lines.last) as Map<String, dynamic>;
      expect(footer['outcome'], 'harness_error', reason: testCase.label);
      expect(footer['harness_error'], 'config_error', reason: testCase.label);
    }
  });

  test(
    '--summary-json records the exit code and footer of a failed run',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-summary-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
      final File summary = File(p.join(temp.path, 'nested', 'summary.json'));
      final File errorFile = File(p.join(temp.path, 'stderr.txt'));
      final IOSink errorSink = errorFile.openWrite();

      late final int exitCode;
      try {
        exitCode = await runCli(
          <String>[
            ..._arguments(trajectory.path),
            '--summary-json',
            summary.path,
          ],
          stdin: stdin,
          stdout: stdout,
          stderr: errorSink,
          acpProviderBuilder: (AcpAgentSpec spec) =>
              Future<ModelProvider>.error(
                StateError('missing configuration'),
                StackTrace.current,
              ),
        );
      } finally {
        await errorSink.close();
      }

      expect(exitCode, 1);
      final Map<String, dynamic> json =
          jsonDecode(await summary.readAsString()) as Map<String, dynamic>;
      expect(json['schema'], 'leonard.run_summary/1');
      expect(json['exit_code'], 1);
      expect(json['outcome'], 'harness_error');
      expect(json['harness_error'], 'config_error');
      expect(json['total_turns'], 0);
      expect(json['trajectory'], trajectory.path);
      expect(json['model_identifier'], 'acp:codex-acp');
      // No model was ever built, so there is no usage to report.
      expect(json['usage'], isNull);
      expect(json['verdict'], 'infra');
      expect(json['reason'], contains('[config_error]'));
      expect(json['digest'], isEmpty);
    },
  );

  test(
    '--gate-exit-codes exits 75 when the run never judged the app',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-gate-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
      final File summary = File(p.join(temp.path, 'summary.json'));
      final File errorFile = File(p.join(temp.path, 'stderr.txt'));
      final IOSink errorSink = errorFile.openWrite();

      late final int configExit;
      late final int usageExit;
      try {
        configExit = await runCli(
          <String>[
            ..._arguments(trajectory.path),
            '--summary-json',
            summary.path,
            '--gate-exit-codes',
          ],
          stdin: stdin,
          stdout: stdout,
          stderr: errorSink,
          acpProviderBuilder: (AcpAgentSpec spec) =>
              Future<ModelProvider>.error(
                StateError('missing configuration'),
                StackTrace.current,
              ),
        );
        usageExit = await runCli(
          <String>['--gate-exit-codes', '--policy', 'nonsense'],
          stdin: stdin,
          stdout: stdout,
          stderr: errorSink,
        );
      } finally {
        await errorSink.close();
      }

      expect(configExit, 75);
      final Map<String, dynamic> json =
          jsonDecode(await summary.readAsString()) as Map<String, dynamic>;
      expect(json['exit_code'], 75);
      expect(json['verdict'], 'infra');
      expect(usageExit, 75);
      expect(
        await errorFile.readAsString(),
        contains('verdict: infra — usage error'),
      );
    },
  );

  test('a malformed LEONARD_PRICE env pair is a usage error', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'leonard-price-env-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
    final File errorFile = File(p.join(temp.path, 'stderr.txt'));
    final IOSink errorSink = errorFile.openWrite();

    late final int exitCode;
    try {
      exitCode = await runCli(
        _qwenArguments(trajectory.path),
        stdin: stdin,
        stdout: stdout,
        stderr: errorSink,
        providerEnvironment: <String, String>{
          'LEONARD_PRICE_INPUT_PER_MTOK': '0.1',
        },
      );
    } finally {
      await errorSink.close();
    }

    expect(exitCode, 64);
    expect(
      await errorFile.readAsString(),
      contains('LEONARD_PRICE_INPUT_PER_MTOK / LEONARD_PRICE_OUTPUT_PER_MTOK'),
    );
  });

  test(
    'malformed swift-infer endpoint is a configuration error and a valid endpoint builds',
    () async {
      for (final String endpoint in <String>[
        'not a uri',
        'https:///missing-host',
      ]) {
        final Directory temp = await Directory.systemTemp.createTemp(
          'leonard-provider-endpoint-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final File trajectory = File(p.join(temp.path, 'trajectory.jsonl'));
        final File errorFile = File(p.join(temp.path, 'stderr.txt'));
        final IOSink errorSink = errorFile.openWrite();

        late final int exitCode;
        try {
          exitCode = await runCli(
            _qwenArguments(trajectory.path),
            stdin: stdin,
            stdout: stdout,
            stderr: errorSink,
            providerEnvironment: <String, String>{
              'SWIFT_INFER_ENDPOINT': endpoint,
            },
          );
        } finally {
          await errorSink.close();
        }

        expect(exitCode, 1, reason: endpoint);
        expect(
          await errorFile.readAsString(),
          'error: CliUsageError: Invalid SWIFT_INFER_ENDPOINT: "$endpoint" '
          '(expected an absolute URI with scheme and host)\n',
          reason: endpoint,
        );
        final List<String> lines = await trajectory.readAsLines();
        final Map<String, dynamic> footer =
            jsonDecode(lines.last) as Map<String, dynamic>;
        expect(footer['outcome'], 'harness_error', reason: endpoint);
        expect(footer['harness_error'], 'config_error', reason: endpoint);
      }

      final ModelProvider provider = await buildProvider(
        ModelTier.qwenMlx,
        sessionId: 'session',
        environment: <String, String>{
          'SWIFT_INFER_ENDPOINT': 'https://swift.example:8443',
        },
      );
      expect(provider, isA<DartanticModelProvider>());
      final SwiftInferBackend backend =
          (provider as DartanticModelProvider).backend as SwiftInferBackend;
      expect(backend.baseUrl, Uri.parse('https://swift.example:8443'));
    },
  );
}

List<String> _arguments(String trajectoryPath) => <String>[
  '--goal',
  'exercise provider construction',
  '--vm-uri',
  'ws://127.0.0.1:1/ws',
  '--harness',
  'codex',
  '--output',
  trajectoryPath,
];

List<String> _qwenArguments(String trajectoryPath) => <String>[
  '--goal',
  'exercise provider construction',
  '--vm-uri',
  'ws://127.0.0.1:1/ws',
  '--model',
  'qwen-mlx',
  '--output',
  trajectoryPath,
];
