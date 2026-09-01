import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String repositoryRoot = _findRepositoryRoot();
  final File scenario = File(
    p.join(
      repositoryRoot,
      'packages',
      'leonard_cli',
      'scenarios',
      'leonard_devtools_panel.md',
    ),
  );
  final File runner = File(
    p.join(repositoryRoot, 'tool', 'run_panel_selfdrive_scenario.sh'),
  );
  final File manualSmoke = File(
    p.join(repositoryRoot, 'docs', 'leonard_devtools_manual_smoke.md'),
  );
  final String verifier = p.join(
    repositoryRoot,
    'tool',
    'verify_panel_selfdrive_receipt.dart',
  );

  test('scenario covers every automated panel checkpoint', () {
    final String source = scenario.readAsStringSync();
    for (final String expected in <String>[
      r'${SWIFT_INFER_ENDPOINT}',
      r'${SWIFT_INFER_AGENT_TOKEN}',
      r'${PANEL_SELFDRIVE_MODEL_ID}',
      'Test connection',
      'OK (N models)',
      'Start',
      'Timeline',
      'Proposed action',
      'Stop',
      'SessionEnded',
    ]) {
      expect(source, contains(expected), reason: 'missing $expected');
    }
  });

  test('runner composes the harness, scenario, environment, and verifier', () {
    final String source = runner.readAsStringSync();
    for (final String expected in <String>[
      'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
      'tool/run_panel_selfdrive.sh',
      '--goal-file',
      '--action-env SWIFT_INFER_ENDPOINT',
      '--action-env SWIFT_INFER_AGENT_TOKEN',
      '--action-env PANEL_SELFDRIVE_MODEL_ID',
      'tool/verify_panel_selfdrive_receipt.dart',
    ]) {
      expect(source, contains(expected), reason: 'missing $expected');
    }
  });

  test('manual smoke retains only genuine manual work', () {
    final String source = manualSmoke.readAsStringSync();
    for (final String expected in <String>[
      'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
      'tool/run_panel_selfdrive_scenario.sh',
      'tool/run_panel_selfdrive.sh',
    ]) {
      expect(source, contains(expected), reason: 'missing $expected');
    }

    final List<String> sections = source.split('## Manual remainder');
    expect(sections, hasLength(2));
    final String remainder = sections.last;
    for (final String automatedInstruction in <String>[
      'Test connection',
      'press Start',
      'Timeline tab',
      'press Stop',
    ]) {
      expect(
        remainder,
        isNot(contains(automatedInstruction)),
        reason: 'manual remainder repeats $automatedInstruction',
      );
    }
  });

  test(
    'receipt verifier accepts checkpoints and rejects a secret leak',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'panel-selfdrive-receipt-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'outer.jsonl'));
      final File driverLog = File(p.join(temp.path, 'driver.log'));
      final File harnessLog = File(p.join(temp.path, 'harness.log'));
      await trajectory.writeAsString(_validTrajectoryFixture());
      await driverLog.writeAsString('driver completed\n');
      await harnessLog.writeAsString('harness completed\n');

      const String fixtureSecret = 'LEONARD_TEST_RECEIPT_SECRET';
      final List<String> arguments = <String>[
        'run',
        verifier,
        trajectory.path,
        driverLog.path,
        harnessLog.path,
      ];
      final ProcessResult safe = await Process.run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: repositoryRoot,
        environment: const <String, String>{
          'SWIFT_INFER_AGENT_TOKEN': fixtureSecret,
        },
      );
      expect(safe.exitCode, 0, reason: 'stderr: ${safe.stderr}');
      expect(safe.stdout, contains('PROMPT_FORM=enabled'));
      expect(safe.stdout, contains('CAPTURED_OUTPUT_SECRET_SCAN=clean'));

      await driverLog.writeAsString('$fixtureSecret\n');
      final ProcessResult leak = await Process.run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: repositoryRoot,
        environment: const <String, String>{
          'SWIFT_INFER_AGENT_TOKEN': fixtureSecret,
        },
      );
      expect(leak.exitCode, 2);
      expect(leak.stdout, isNot(contains(fixtureSecret)));
      expect(leak.stderr, isNot(contains(fixtureSecret)));
    },
  );
}

String _validTrajectoryFixture() {
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[
    _enterTextTurn(0, r'${SWIFT_INFER_ENDPOINT}'),
    _enterTextTurn(1, r'${SWIFT_INFER_AGENT_TOKEN}'),
    _enterTextTurn(2, r'${PANEL_SELFDRIVE_MODEL_ID}'),
    _turnWithText(3, 'OK (2 models)'),
    _turnWithNodes(4, <Map<String, dynamic>>[
      <String, dynamic>{'label': '#0 core.done()'},
      <String, dynamic>{'label': 'Proposed action'},
      <String, dynamic>{'value': 'core.done()'},
    ]),
    <String, dynamic>{
      'type': 'turn',
      'index': 5,
      'observation': <String, dynamic>{
        'core': <String, dynamic>{
          'nodes': <Map<String, dynamic>>[
            <String, dynamic>{
              'label': 'Start',
              'actions': <String>['tap'],
              'state': <String>[],
            },
          ],
        },
      },
      'proposed_action': <String, dynamic>{
        'tool': 'core.done',
        'args': <String, dynamic>{
          'reason': 'panel smoke passed: inner turn 0 tool core.done',
        },
      },
    },
  ];
  return '${records.map(jsonEncode).join('\n')}\n';
}

Map<String, dynamic> _enterTextTurn(int index, String text) =>
    <String, dynamic>{
      'type': 'turn',
      'index': index,
      'observation': <String, dynamic>{
        'core': <String, dynamic>{'nodes': <dynamic>[]},
      },
      'proposed_action': <String, dynamic>{
        'tool': 'core.enter_text',
        'args': <String, dynamic>{'text': text},
      },
    };

Map<String, dynamic> _turnWithText(int index, String text) =>
    _turnWithNodes(index, <Map<String, dynamic>>[
      <String, dynamic>{'label': text},
    ]);

Map<String, dynamic> _turnWithNodes(
  int index,
  List<Map<String, dynamic>> nodes,
) => <String, dynamic>{
  'type': 'turn',
  'index': index,
  'observation': <String, dynamic>{
    'core': <String, dynamic>{'nodes': nodes},
  },
  'proposed_action': <String, dynamic>{
    'tool': 'core.tap',
    'args': <String, dynamic>{},
  },
};

String _findRepositoryRoot() {
  Directory directory = Directory.current.absolute;
  for (int i = 0; i < 8; i++) {
    if (File(
          p.join(directory.path, 'tool', 'run_panel_selfdrive.sh'),
        ).existsSync() &&
        File(
          p.join(directory.path, 'packages', 'leonard_cli', 'pubspec.yaml'),
        ).existsSync()) {
      return directory.path;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('could not find repository root from ${Directory.current}');
}
