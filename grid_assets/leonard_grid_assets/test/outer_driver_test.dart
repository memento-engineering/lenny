import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

const String _reason =
    r'^panel smoke passed: inner turn \d+ tool [A-Za-z0-9_.]+$';
const String _evidence = r'^#([0-9]+) ([A-Za-z0-9_.-]+)\(';

void main() {
  group('scenarioPatterns', () {
    test('reads the real scenario header declarations', () {
      final ScenarioPatterns patterns = scenarioPatterns('''
Drive the Leonard debug panel through this complete smoke.
done-reason-pattern: $_reason
done-evidence-pattern: $_evidence
''');
      expect(patterns.doneReason, _reason);
      expect(patterns.doneEvidence, _evidence);
    });

    test('throws when either declaration is absent', () {
      expect(
        () => scenarioPatterns('done-evidence-pattern: $_evidence'),
        throwsFormatException,
      );
      expect(
        () => scenarioPatterns('done-reason-pattern: $_reason'),
        throwsFormatException,
      );
    });
  });

  test('shellQuote quotes plain words and embedded apostrophes', () {
    expect(shellQuote('plain'), "'plain'");
    expect(shellQuote("it's"), r"'it'\''s'");
  });

  test('outerDriverShellCommand preserves the manual driver contract', () {
    final String command = outerDriverShellCommand(
      repoRoot: '/repo',
      scenarioPath: '/repo/scenario.md',
      panelDwdsUri: 'ws://panel',
      trajectoryPath: '/run/outer.jsonl',
      driverLogPath: '/run/driver.log',
      probeArtifactPath: '/run/panel_probe.json',
      driverStatusPath: '/run/driver.status',
      patterns: const ScenarioPatterns(
        doneReason: _reason,
        doneEvidence: _evidence,
      ),
    );
    expect(command, contains("'--vm-uri' 'ws://panel'"));
    expect(command, contains("'--goal-file' '/repo/scenario.md'"));
    expect(command, contains("'--model' 'qwen-mlx'"));
    expect(command, contains("'--turn-budget' '180'"));
    expect(command, contains("'--done-reason-pattern' '$_reason'"));
    expect(command, contains("'--done-evidence-pattern' '$_evidence'"));
    expect(command, contains("'--action-env' 'SWIFT_INFER_ENDPOINT'"));
    expect(command, contains("'--action-env' 'SWIFT_INFER_AGENT_TOKEN'"));
    expect(command, contains("'--action-env' 'PANEL_SELFDRIVE_MODEL_ID'"));
    expect(
      command,
      endsWith(
        "> '/run/driver.log' 2>&1; "
        "printf '%s\\n' \"\$?\" > '/run/driver.status'; exit 0",
      ),
    );
  });

  test('interpretEvent handles every runtime event', () {
    const OuterDriverCapability capability = OuterDriverCapability();
    expect(
      capability.interpretEvent(const Exited(name: 'x', exitCode: 0)),
      StepSignal.complete,
    );
    expect(
      capability.interpretEvent(const Exited(name: 'x', exitCode: 3)),
      StepSignal.failed,
    );
    expect(capability.interpretEvent(const Died(name: 'x')), StepSignal.failed);
    expect(
      capability.interpretEvent(const SessionStarted(name: 'x', pid: 1)),
      StepSignal.none,
    );
    expect(
      capability.interpretEvent(const Respawned(name: 'x', epoch: 1)),
      StepSignal.none,
    );
    expect(
      capability.interpretEvent(const ActivityChanged(name: 'x', active: true)),
      StepSignal.none,
    );
  });
}
