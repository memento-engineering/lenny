import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

const String _model = 'qwen3.6-35b-a3b-8bit';
const String _trajectory = '''
{"type":"turn","index":2,"proposed_action":{"tool":"core.tap"},"model_metadata":{"served_model_id":"z-model"}}
{"type":"turn","index":3,"proposed_action":{"tool":"core.done"},"model_metadata":{"served_model_id":"a-model"}}
{"type":"footer","termination_detail":"done pattern matched"}
''';

class _RecordingShellRunner implements ShellRunner {
  _RecordingShellRunner(this.results);

  final List<ShellRunResult> results;
  final List<({String workingDirectory, String command})> calls =
      <({String workingDirectory, String command})>[];

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async {
    calls.add((workingDirectory: workingDirectory, command: command));
    return results[calls.length - 1];
  }
}

Bead _bead() => const Bead(
  id: 'work',
  metadata: <String, dynamic>{
    kSelfdriveScenarioKey:
        'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
    kSelfdriveOuterModelKey: _model,
    kSelfdriveInnerModelKey: _model,
  },
);

FakeTreeContext _context(String runDir) => FakeTreeContext(
  values: <Type, Object>{
    Bead: _bead(),
    Workspace: const Workspace(
      workspaceDir: '/repo',
      branch: 'grid/work',
      baseBranch: 'main',
    ),
    SiblingView: SiblingView(
      results: <String, Map<String, String>>{
        'work/selfdrive/$kSelfdriveOuterDriverStep': <String, String>{
          kSelfdriveRunDirKey: runDir,
          kSelfdriveTrajectoryKey: '$runDir/outer.jsonl',
          kSelfdriveDriverStatusKey: '$runDir/driver.status',
        },
      },
    ),
  },
);

void main() {
  test('parseReceiptFields keeps receipt fields and drops diagnostics', () {
    expect(
      parseReceiptFields('''
TURN_COUNT=4
panel self-drive receipt invalid: missing capture
INNER_PANEL_MODEL_RESOLVED=$_model
'''),
      <String, String>{'TURN_COUNT': '4', 'INNER_PANEL_MODEL_RESOLVED': _model},
    );
  });

  test('trajectoryMetrics reads both served ids and first-turn evidence', () {
    expect(trajectoryMetrics(_trajectory), <String, String>{
      'TURN_FIRST_INDEX': '2',
      'TURN_FIRST_TOOL': 'core.tap',
      'TURN_FIRST_SERVED_MODEL_ID': 'z-model',
      'OUTER_SERVED_MODEL_IDS': 'a-model,z-model',
      'FURTHEST_POINT':
          'outer trajectory turn 3, proposed_action.tool=core.done',
      'TERMINATION_DETAIL': 'done pattern matched',
    });
  });

  test('trajectoryMetrics skips a truncated final JSONL line', () {
    final Map<String, String> metrics = trajectoryMetrics(
      '$_trajectory{"type":"turn"',
    );
    expect(metrics['OUTER_SERVED_MODEL_IDS'], 'a-model,z-model');
    expect(metrics['TERMINATION_DETAIL'], 'done pattern matched');
  });

  test('trajectoryMetrics names the furthest point from the last turn', () {
    expect(
      trajectoryMetrics(_trajectory)['FURTHEST_POINT'],
      'outer trajectory turn 3, proposed_action.tool=core.done',
    );
    expect(
      trajectoryMetrics('')['FURTHEST_POINT'],
      'outer trajectory turn unknown, proposed_action.tool=unknown',
    );
  });

  test('failingAssertion reads the verifier refusal, else none', () {
    expect(
      failingAssertion(
        'TURN_COUNT=4\n'
        'panel self-drive receipt invalid: no running-session Stop button '
        'observed after Start\n',
      ),
      'no running-session Stop button observed after Start',
    );
    expect(failingAssertion('TURN_COUNT=4\n'), 'none');
  });

  test('selfdriveReceiptLines carries every bead-required field', () {
    List<String> lines(int status) => selfdriveReceiptLines(
      runHead: 'abc123',
      runDir: '/run',
      requestedModelId: _model,
      scenarioExitStatus: '3',
      verifierExitStatus: status,
      failingAssertionText: status == 0 ? 'none' : 'no Stop button',
      verifierFields: const <String, String>{
        'INNER_PANEL_MODEL_RESOLVED': _model,
        'CAPTURED_OUTPUT_SECRET_SCAN': 'clean',
        'TURN_COUNT': '13',
        'STOP_OBSERVED': 'true',
        'OBSERVED_TURN_INDEX': '0',
        'OBSERVED_TURN_TOOL': 'core.done',
        'PROMPT_FORM': 'enabled',
      },
      metrics: trajectoryMetrics(_trajectory),
    );

    expect(lines(0).first, 'PANEL_SELFDRIVE_ROUND=10');
    expect(lines(0), contains('PANEL_SELFDRIVE_RECEIPT=passed'));
    expect(lines(1), contains('PANEL_SELFDRIVE_RECEIPT=failed'));
    expect(lines(0), contains('RECEIPT_PATH=station-circuit'));
    expect(lines(0), contains('RUN_HEAD=abc123'));
    expect(lines(0), contains('SCENARIO_EXIT_STATUS=3'));
    expect(lines(0), contains('VERIFIER_EXIT_STATUS=0'));
    expect(lines(0), contains('TURN_COUNT=13'));
    expect(lines(0), contains('STOP_OBSERVED=true'));
    expect(lines(0), contains('PROMPT_FORM=enabled'));
    expect(lines(0), contains('OBSERVED_TURN_INDEX=0'));
    expect(lines(0), contains('OBSERVED_TURN_TOOL=core.done'));
    expect(lines(0), contains('FAILING_ASSERTION=none'));
    expect(lines(1), contains('FAILING_ASSERTION=no Stop button'));
    expect(
      lines(0),
      contains(
        'FURTHEST_POINT=outer trajectory turn 3, '
        'proposed_action.tool=core.done',
      ),
    );
    expect(lines(0), contains('OUTER_DRIVER_MODEL_ID=$_model'));
    expect(lines(0), contains('INNER_PANEL_MODEL_ID=$_model'));
    expect(lines(0), contains('OUTER_SERVED_MODEL_IDS=a-model,z-model'));
    expect(lines(0), contains('TERMINATION_DETAIL=done pattern matched'));
  });

  for (final int verifierStatus in <int>[0, 1]) {
    test(
      'verify appends the exact station receipt on exit $verifierStatus',
      () async {
        const String runDir = '/run/panel-selfdrive-test';
        final _RecordingShellRunner shell =
            _RecordingShellRunner(<ShellRunResult>[
              const ShellRunResult(exitCode: 0, output: 'abc123\n'),
              ShellRunResult(
                exitCode: verifierStatus,
                output:
                    'INNER_PANEL_MODEL_RESOLVED=$_model\n'
                    'CAPTURED_OUTPUT_SECRET_SCAN=clean\n',
              ),
            ]);
        final List<({String beadId, String note})> notes =
            <({String beadId, String note})>[];
        final Map<String, String> files = <String, String>{
          '$runDir/outer.jsonl': _trajectory,
          '$runDir/driver.status': '3\n',
        };
        final SelfdriveVerifyCapability capability = SelfdriveVerifyCapability(
          appendNote: (String beadId, String note) async {
            notes.add((beadId: beadId, note: note));
          },
          shell: shell,
          readFile: (String path) => files[path] ?? '',
        );

        final StepOutcome outcome = await capability.run(
          _context(runDir),
          stepArgs('work/selfdrive/verify'),
        );

        expect(outcome, verifierStatus == 0 ? isA<Ok>() : isA<Failed>());
        expect(shell.calls, hasLength(2));
        expect(shell.calls[0].command, 'git rev-parse HEAD');
        expect(
          shell.calls[1].command,
          startsWith("PANEL_SELFDRIVE_MODEL_ID='$_model' dart run "),
        );
        expect(
          shell.calls[1].command,
          contains('tool/verify_panel_selfdrive_receipt.dart'),
        );
        expect(notes, hasLength(1));
        expect(notes.single.beadId, 'work');
        expect(
          notes.single.note,
          selfdriveReceiptLines(
            runHead: 'abc123',
            runDir: runDir,
            requestedModelId: _model,
            scenarioExitStatus: '3',
            verifierExitStatus: verifierStatus,
            failingAssertionText: 'none',
            verifierFields: const <String, String>{
              'INNER_PANEL_MODEL_RESOLVED': _model,
              'CAPTURED_OUTPUT_SECRET_SCAN': 'clean',
            },
            metrics: trajectoryMetrics(_trajectory),
          ).join('\n'),
        );
      },
    );
  }
}
