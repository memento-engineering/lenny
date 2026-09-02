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

  test('selfdriveReceiptLines reflects verifier success and failure', () {
    List<String> lines(int status) => selfdriveReceiptLines(
      runHead: 'abc123',
      runDir: '/run',
      requestedModelId: _model,
      verifierExitStatus: status,
      verifierFields: const <String, String>{
        'INNER_PANEL_MODEL_RESOLVED': _model,
        'CAPTURED_OUTPUT_SECRET_SCAN': 'clean',
      },
      metrics: trajectoryMetrics(_trajectory),
    );

    expect(lines(0).first, 'PANEL_SELFDRIVE_RECEIPT=passed');
    expect(lines(1).first, 'PANEL_SELFDRIVE_RECEIPT=failed');
    expect(lines(0), contains('RUN_HEAD=abc123'));
    expect(lines(0), contains('OUTER_SERVED_MODEL_IDS=a-model,z-model'));
    expect(lines(0), contains('INNER_PANEL_MODEL_RESOLVED=$_model'));
    expect(lines(0), contains('TURN_FIRST_INDEX=2'));
    expect(lines(0), contains('TURN_FIRST_TOOL=core.tap'));
    expect(lines(0), contains('TURN_FIRST_SERVED_MODEL_ID=z-model'));
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
        final SelfdriveVerifyCapability capability = SelfdriveVerifyCapability(
          appendNote: (String beadId, String note) async {
            notes.add((beadId: beadId, note: note));
          },
          shell: shell,
          readFile: (String path) {
            expect(path, '$runDir/outer.jsonl');
            return _trajectory;
          },
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
            verifierExitStatus: verifierStatus,
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
