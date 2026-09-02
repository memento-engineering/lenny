/// The outer `leonard_cli` driver step.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show parentPath;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import 'selfdrive_circuit.dart';
import 'selfdrive_preflight.dart' show EnvLookup, kSelfdriveClearedModelKey;

/// Scenario-declared completion gates.
class ScenarioPatterns {
  /// Creates a pair of completion patterns.
  const ScenarioPatterns({
    required this.doneReason,
    required this.doneEvidence,
  });

  /// The `done-reason-pattern` regular expression.
  final String doneReason;

  /// The `done-evidence-pattern` regular expression.
  final String doneEvidence;
}

/// Reads both required completion gates from scenario markdown.
ScenarioPatterns scenarioPatterns(String scenarioText) {
  String read(String key) {
    for (final String line in const LineSplitter().convert(scenarioText)) {
      if (line.startsWith('$key: ')) {
        return line.substring(key.length + 2).trim();
      }
    }
    throw FormatException('scenario declares no $key');
  }

  return ScenarioPatterns(
    doneReason: read('done-reason-pattern'),
    doneEvidence: read('done-evidence-pattern'),
  );
}

/// Quotes one POSIX shell word.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Builds the bounded outer-driver command used by the station process step.
///
/// The wrapper always exits zero: the driver's own status is receipt DATA
/// written to [driverStatusPath], never the circuit's verdict, so the terminal
/// `verify` step still runs and records a negative receipt.
String outerDriverShellCommand({
  required String repoRoot,
  required String scenarioPath,
  required String panelDwdsUri,
  required String trajectoryPath,
  required String driverLogPath,
  required String probeArtifactPath,
  required String driverStatusPath,
  required ScenarioPatterns patterns,
  int turnBudget = 180,
  int coreBudgetBytes = 131072,
}) {
  final List<String> argv = <String>[
    'dart',
    'run',
    p.join(repoRoot, 'packages', 'leonard_cli', 'bin', 'leonard_cli.dart'),
    '--vm-uri',
    panelDwdsUri,
    '--goal-file',
    scenarioPath,
    '--model',
    'qwen-mlx',
    '--output',
    trajectoryPath,
    '--turn-budget',
    '$turnBudget',
    '--done-reason-pattern',
    patterns.doneReason,
    '--done-evidence-pattern',
    patterns.doneEvidence,
    '--core-budget-bytes',
    '$coreBudgetBytes',
    '--probe-artifact',
    probeArtifactPath,
    '--action-env',
    'SWIFT_INFER_ENDPOINT',
    '--action-env',
    'SWIFT_INFER_AGENT_TOKEN',
    '--action-env',
    'PANEL_SELFDRIVE_MODEL_ID',
  ];
  return '${argv.map(shellQuote).join(' ')} '
      '> ${shellQuote(driverLogPath)} 2>&1; '
      "printf '%s\\n' \"\$?\" > ${shellQuote(driverStatusPath)}; "
      'exit 0';
}

/// Runs one outer driver against the endpoint published by the harness.
class OuterDriverCapability extends ProcessCapability {
  /// Creates the capability over injectable environment and deadline values.
  const OuterDriverCapability({
    EnvLookup env = _systemEnv,
    Duration deadline = const Duration(minutes: 45),
  }) : _env = env,
       _deadline = deadline;

  static String? _systemEnv(String name) => Platform.environment[name];

  final EnvLookup _env;
  final Duration _deadline;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final _OuterDriverPlan plan = _plan(context, args);
    return RuntimeConfig(
      workDir: plan.repoRoot,
      command: 'bash',
      args: <String>['-c', plan.command],
      lifecycle: Lifecycle.oneTurn,
      env: <String, String>{
        'SWIFT_INFER_ENDPOINT': _env('SWIFT_INFER_ENDPOINT') ?? '',
        'SWIFT_INFER_AGENT_TOKEN': _env('SWIFT_INFER_AGENT_TOKEN') ?? '',
        'SWIFT_INFER_MODEL': plan.modelId,
        'PANEL_SELFDRIVE_MODEL_ID': plan.modelId,
      },
      deadline: _deadline,
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final int exitCode) =>
      exitCode == 0 ? StepSignal.complete : StepSignal.failed,
    Died() => StepSignal.failed,
    SessionStarted() || Respawned() || ActivityChanged() => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    final _OuterDriverPlan plan = _plan(context, args);
    return <String, String>{
      kSelfdriveTrajectoryKey: plan.trajectoryPath,
      kSelfdriveRunDirKey: plan.runDir,
      kSelfdriveDriverStatusKey: plan.driverStatusPath,
    };
  }

  _OuterDriverPlan _plan(TreeContext context, StepArgs args) {
    final Workspace workspace =
        context.getInheritedSeedOfExactType<Workspace>() ??
        (throw StateError('selfdrive outer-driver: no ambient Workspace'));
    final Bead bead =
        context.getInheritedSeedOfExactType<Bead>() ??
        (throw StateError('selfdrive outer-driver: no ambient Bead'));
    final SelfdriveOrder order =
        SelfdriveOrder.fromBead(bead) ??
        (throw StateError('selfdrive outer-driver: bead carries no order'));
    final SiblingView siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final String circuitPath = parentPath(args.nodePath);
    final Map<String, String> harness = siblings.resultOf(
      '$circuitPath/$kSelfdrivePanelHarnessStep',
    );
    final String panelUri =
        harness[kPanelDwdsUriKey] ??
        (throw StateError(
          'selfdrive outer-driver: harness published no $kPanelDwdsUriKey',
        ));
    final String runDir =
        harness[kSelfdriveRunDirKey] ??
        (throw StateError(
          'selfdrive outer-driver: harness published no $kSelfdriveRunDirKey',
        ));
    final String modelId =
        siblings.resultOf(
          '$circuitPath/$kSelfdrivePreflightStep',
        )[kSelfdriveClearedModelKey] ??
        order.outerModelId;
    final String scenarioPath = p.join(workspace.workspaceDir, order.scenario);
    final String trajectoryPath = p.join(runDir, 'outer.jsonl');
    final String driverStatusPath = p.join(runDir, 'driver.status');
    return _OuterDriverPlan(
      repoRoot: workspace.workspaceDir,
      runDir: runDir,
      modelId: modelId,
      trajectoryPath: trajectoryPath,
      driverStatusPath: driverStatusPath,
      command: outerDriverShellCommand(
        repoRoot: workspace.workspaceDir,
        scenarioPath: scenarioPath,
        panelDwdsUri: panelUri,
        trajectoryPath: trajectoryPath,
        driverLogPath: p.join(runDir, 'driver.log'),
        probeArtifactPath: p.join(runDir, 'panel_probe.json'),
        driverStatusPath: driverStatusPath,
        patterns: scenarioPatterns(File(scenarioPath).readAsStringSync()),
      ),
    );
  }
}

class _OuterDriverPlan {
  const _OuterDriverPlan({
    required this.repoRoot,
    required this.runDir,
    required this.modelId,
    required this.trajectoryPath,
    required this.driverStatusPath,
    required this.command,
  });

  final String repoRoot;
  final String runDir;
  final String modelId;
  final String trajectoryPath;
  final String driverStatusPath;
  final String command;
}
