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
