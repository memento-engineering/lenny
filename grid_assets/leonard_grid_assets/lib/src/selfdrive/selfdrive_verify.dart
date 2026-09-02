/// The terminal verifier and station-written receipt.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show ShellRunResult, ShellRunner, SystemShellRunner, parentPath;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show WorkNoteAppender;
import 'package:path/path.dart' as p;

import 'selfdrive_circuit.dart';

/// Parses upper-snake `KEY=value` lines from verifier output.
Map<String, String> parseReceiptFields(String output) {
  final RegExp line = RegExp(r'^([A-Z][A-Z0-9_]*)=(.*)$');
  return <String, String>{
    for (final String raw in const LineSplitter().convert(output))
      if (line.firstMatch(raw.trim()) case final RegExpMatch match)
        match.group(1)!: match.group(2)!,
  };
}

/// Derives station-owned metrics from an outer trajectory.
Map<String, String> trajectoryMetrics(String trajectoryJsonl) {
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[
    for (final String raw in const LineSplitter().convert(trajectoryJsonl))
      if (raw.trim().isNotEmpty)
        if (_decode(raw) case final Map<String, dynamic> record) record,
  ];
  final List<Map<String, dynamic>> turns = records
      .where((Map<String, dynamic> record) => record['type'] == 'turn')
      .toList(growable: false);
  final Set<String> served = <String>{
    for (final Map<String, dynamic> turn in turns)
      if (_nestedString(turn, 'model_metadata', 'served_model_id')
          case final String id)
        id,
  };
  final Map<String, dynamic> footer = records.lastWhere(
    (Map<String, dynamic> record) => record['type'] == 'footer',
    orElse: () => const <String, dynamic>{},
  );
  final Map<String, dynamic> first = turns.isEmpty
      ? const <String, dynamic>{}
      : turns.first;
  return <String, String>{
    'TURN_FIRST_INDEX': '${first['index'] ?? 'absent'}',
    'TURN_FIRST_TOOL':
        _nestedString(first, 'proposed_action', 'tool') ?? 'absent',
    'TURN_FIRST_SERVED_MODEL_ID':
        _nestedString(first, 'model_metadata', 'served_model_id') ?? 'absent',
    'OUTER_SERVED_MODEL_IDS': served.isEmpty
        ? 'absent'
        : (served.toList()..sort()).join(','),
    'TERMINATION_DETAIL': '${footer['termination_detail'] ?? 'none'}',
  };
}

String? _nestedString(Map<String, dynamic> record, String parent, String key) {
  final Object? value = record[parent];
  if (value is! Map<String, dynamic>) return null;
  final Object? nested = value[key];
  return nested is String ? nested : null;
}

Map<String, dynamic>? _decode(String raw) {
  try {
    final Object? value = jsonDecode(raw);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

String _readSelfdriveFile(String path) {
  final File file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// Builds the exact receipt block appended to the work bead by the station.
List<String> selfdriveReceiptLines({
  required String runHead,
  required String runDir,
  required String requestedModelId,
  required int verifierExitStatus,
  required Map<String, String> verifierFields,
  required Map<String, String> metrics,
}) => <String>[
  'PANEL_SELFDRIVE_RECEIPT=${verifierExitStatus == 0 ? 'passed' : 'failed'}',
  'RUN_HEAD=$runHead',
  'RUN_DIR=$runDir',
  'VERIFIER_EXIT_STATUS=$verifierExitStatus',
  'OUTER_DRIVER_MODEL_REQUESTED=$requestedModelId',
  'OUTER_SERVED_MODEL_IDS=${metrics['OUTER_SERVED_MODEL_IDS'] ?? 'absent'}',
  'INNER_PANEL_MODEL_RESOLVED='
      '${verifierFields['INNER_PANEL_MODEL_RESOLVED'] ?? 'absent'}',
  'TURN_FIRST_INDEX=${metrics['TURN_FIRST_INDEX'] ?? 'absent'}',
  'TURN_FIRST_TOOL=${metrics['TURN_FIRST_TOOL'] ?? 'absent'}',
  'TURN_FIRST_SERVED_MODEL_ID='
      '${metrics['TURN_FIRST_SERVED_MODEL_ID'] ?? 'absent'}',
  'TERMINATION_DETAIL=${metrics['TERMINATION_DETAIL'] ?? 'none'}',
  'CAPTURED_OUTPUT_SECRET_SCAN='
      '${verifierFields['CAPTURED_OUTPUT_SECRET_SCAN'] ?? 'absent'}',
];

/// Runs the established verifier and appends its station-derived receipt.
class SelfdriveVerifyCapability extends ServiceCapability {
  /// Creates the verifier over station-owned note, shell, and file seams.
  const SelfdriveVerifyCapability({
    required WorkNoteAppender appendNote,
    ShellRunner shell = const SystemShellRunner(),
    String Function(String path) readFile = _readSelfdriveFile,
  }) : _appendNote = appendNote,
       _shell = shell,
       _readFile = readFile;

  final WorkNoteAppender _appendNote;
  final ShellRunner _shell;
  final String Function(String path) _readFile;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final Workspace? workspace = context
        .getInheritedSeedOfExactType<Workspace>();
    final Bead? bead = context.getInheritedSeedOfExactType<Bead>();
    final SelfdriveOrder? order = bead == null
        ? null
        : SelfdriveOrder.fromBead(bead);
    if (workspace == null || order == null) {
      return const Failed('selfdrive verify: no ambient Workspace or order');
    }
    final SiblingView siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final String circuitPath = parentPath(args.nodePath);
    final Map<String, String> driver = siblings.resultOf(
      '$circuitPath/$kSelfdriveOuterDriverStep',
    );
    final String runDir = driver[kSelfdriveRunDirKey] ?? '';
    if (runDir.isEmpty) {
      return const Failed(
        'selfdrive verify: the outer driver published no run directory',
      );
    }
    final String trajectory =
        driver[kSelfdriveTrajectoryKey] ?? p.join(runDir, 'outer.jsonl');
    final ShellRunResult head = await _shell.run(
      workingDirectory: workspace.workspaceDir,
      command: 'git rev-parse HEAD',
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final ShellRunResult verified = await _shell.run(
      workingDirectory: workspace.workspaceDir,
      command:
          'PANEL_SELFDRIVE_MODEL_ID=${_q(order.outerModelId)} '
          'dart run tool/verify_panel_selfdrive_receipt.dart '
          '${_q(trajectory)} '
          '${_q(p.join(runDir, 'driver.log'))} '
          '${_q(p.join(runDir, 'harness.log'))} '
          '${_q(p.join(runDir, 'panel_probe.json'))} '
          '${_q(p.join(runDir, 'panel.log'))} '
          '${_q(p.join(runDir, 'sample_app.log'))}',
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final List<String> receipt = selfdriveReceiptLines(
      runHead: head.ok ? head.output.trim() : 'unknown',
      runDir: runDir,
      requestedModelId: order.outerModelId,
      verifierExitStatus: verified.exitCode,
      verifierFields: parseReceiptFields(verified.output),
      metrics: trajectoryMetrics(_readFile(trajectory)),
    );
    await _appendNote(args.beadId, receipt.join('\n'));
    return verified.ok
        ? const Ok(<String, String>{'PANEL_SELFDRIVE_RECEIPT': 'passed'})
        : Failed(
            'selfdrive verify: receipt refused (exit ${verified.exitCode})',
          );
  }
}

String _q(String value) => "'${value.replaceAll("'", r"'\''")}'";
