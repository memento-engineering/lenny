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
      'Outer-action guard for this smoke',
      r'core.wait {"seconds": 2}',
      r'core.scroll {"node_id": 1, "axis": "vertical", "delta_pixels": 200}',
      'never invent a node id',
      'Correct any failed action before continuing',
      'the INNER goal for the panel',
      'never completion',
      'done-reason-pattern:',
      'done-evidence-pattern:',
      'DISPLAYS a different, resolved value',
      'never re-enter it',
      'the picker labeled `Model`',
      'Reload models',
      'Continue only when `Stop` is visible where `Start` was',
      'is refused',
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
      'PANEL_SELFDRIVE_ARTIFACT_DIR',
      'panel_probe.json',
    ]) {
      expect(source, contains(expected), reason: 'missing $expected');
    }
    expect(source, contains(r'--probe-artifact "$PANEL_PROBE"'));
    expect(source, contains(r'--core-budget-bytes "$CORE_BUDGET_BYTES"'));
    final RegExpMatch? roundMarker = RegExp(
      r"ROUND_MARKER='PANEL_SELFDRIVE_ROUND=([0-9]+)'",
    ).firstMatch(source);
    expect(roundMarker, isNotNull, reason: 'runner declares no ROUND_MARKER');
    expect(int.parse(roundMarker!.group(1)!), greaterThanOrEqualTo(7));
    expect(source, contains(r'grep -Fq "$ROUND_MARKER"'));
    expect(source, contains(r'--done-reason-pattern "$DONE_REASON_PATTERN"'));
    expect(
      source,
      contains(r'--done-evidence-pattern "$DONE_EVIDENCE_PATTERN"'),
    );
    expect(source, contains('--append-notes'));
    expect(source, contains('bd read-back'));
    expect(source, isNot(contains('PANEL_SELFDRIVE_PROBE_BIN')));
    expect(source, isNot(contains('panel_selfdrive_probe.dart')));
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
    'receipt verifier redacts a token leak and treats the endpoint as configuration',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'panel-selfdrive-receipt-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File trajectory = File(p.join(temp.path, 'outer.jsonl'));
      final File driverLog = File(p.join(temp.path, 'driver.log'));
      final File harnessLog = File(p.join(temp.path, 'harness.log'));
      final File panelLog = File(p.join(temp.path, 'panel.log'));
      await trajectory.writeAsString(_validTrajectoryFixture());
      await driverLog.writeAsString('driver completed\n');
      await harnessLog.writeAsString('harness completed\n');
      await panelLog.writeAsString('panel completed\n');

      const String fixtureSecret = 'LEONARD_TEST_RECEIPT_SECRET';
      final List<String> arguments = <String>[
        'run',
        verifier,
        trajectory.path,
        driverLog.path,
        harnessLog.path,
        panelLog.path,
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
      expect(
        leak.stdout,
        contains('CAPTURED_OUTPUT_SECRET_SCAN=leak-redacted'),
      );
      expect(leak.stdout, isNot(contains(fixtureSecret)));
      expect(leak.stderr, isNot(contains(fixtureSecret)));
      final String redactedDriverLog = await driverLog.readAsString();
      expect(redactedDriverLog, contains('<REDACTED:SWIFT_INFER_AGENT_TOKEN>'));
      expect(redactedDriverLog, isNot(contains(fixtureSecret)));

      // The endpoint is configuration, not a credential: the scenario types
      // it into the panel, so it legitimately appears in captures.
      const String fixtureEndpoint = 'https://private-swift.example';
      await panelLog.writeAsString('$fixtureEndpoint\n');
      final ProcessResult endpointPresent = await Process.run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: repositoryRoot,
        environment: const <String, String>{
          'SWIFT_INFER_ENDPOINT': fixtureEndpoint,
        },
      );
      expect(
        endpointPresent.exitCode,
        0,
        reason: 'stderr: ${endpointPresent.stderr}',
      );
      expect(
        endpointPresent.stdout,
        contains('CAPTURED_OUTPUT_SECRET_SCAN=clean'),
      );
      expect(await panelLog.readAsString(), contains(fixtureEndpoint));
    },
  );
}

String _validTrajectoryFixture() {
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[
    _enterTextTurn(0, r'${SWIFT_INFER_ENDPOINT}'),
    _enterTextTurn(1, r'${SWIFT_INFER_AGENT_TOKEN}'),
    _enterTextTurn(2, r'${PANEL_SELFDRIVE_MODEL_ID}'),
    _turnWithNodes(3, <Map<String, dynamic>>[
      <String, dynamic>{'label': 'OK (2 models)'},
      <String, dynamic>{'label': 'Stop'},
    ]),
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
