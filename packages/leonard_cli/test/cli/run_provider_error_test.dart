import 'dart:convert';
import 'dart:io';

import 'package:leonard_acp/leonard_acp.dart' show AcpAgentSpec;
import 'package:leonard_agent/leonard_agent.dart' show ModelProvider;
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
