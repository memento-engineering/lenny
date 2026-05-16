// Dogfood CLI for the exploration agent. See bead lenny-cx6.43.
//
//   dart run packages/exploration_agent/tool/agent_dogfood.dart --help
//   flutter test packages/exploration_agent/tool/agent_dogfood_runner.dart \
//     --dart-define=DOGFOOD_ARGS_JSON='<encoded>'  # ad-hoc run
//
// Why two files? The dogfood harness must boot a real
// `ExplorationBinding` in-process so the agent ↔ binding wire is
// exercised. `package:exploration_flutter` transitively depends on
// `dart:ui` (via `package:flutter`), which cannot compile under plain
// `dart run`. This shim is pure-Dart so the spec's
// `dart run ... --help` validation works; on the happy path it forks
// `flutter test agent_dogfood_runner.dart` with the parsed args
// serialised through `--dart-define`. The runner file owns binding
// boot + harness execution.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

ArgParser _buildParser() => ArgParser()
  ..addOption(
    'goal',
    help: 'goal text inserted into the system prompt',
  )
  ..addOption(
    'tools',
    help: 'comma-separated qualified tool names, e.g. '
        'router.navigate,core.tap',
  )
  ..addOption(
    'endpoint',
    help: 'swift-infer base URL; falls back to SWIFT_INFER_ENDPOINT',
  )
  ..addOption(
    'token',
    help: 'bearer token; falls back to SWIFT_INFER_AGENT_TOKEN',
  )
  ..addOption('model', defaultsTo: 'qwen3.6-27b', help: 'model id')
  ..addOption(
    'observation-fixture',
    help: 'path to a canned core.get_stable_observation JSON fixture',
  )
  ..addOption('max-turns', defaultsTo: '3', help: 'hard cap on loop turns')
  ..addOption(
    'max-turn-budget-ms',
    defaultsTo: '30000',
    help: 'per-turn wall-clock budget in milliseconds',
  )
  ..addFlag(
    'verbose',
    defaultsTo: true,
    help: 'structured per-turn logging (CLI default on)',
  )
  ..addOption(
    'trace-out',
    help: 'where to write the JSONL trace; default '
        '/tmp/agent-dogfood-<unix-ts>.jsonl',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'print usage');

Future<void> main(List<String> argv) async {
  final int code = await _run(argv);
  exitCode = code;
}

Future<int> _run(List<String> argv) async {
  final ArgParser parser = _buildParser();
  final ArgResults r;
  try {
    r = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('argument error: ${e.message}');
    stderr.writeln(parser.usage);
    return 3;
  }
  if (r['help'] as bool) {
    stdout.writeln('agent_dogfood — drive the agent against swift-infer');
    stdout.writeln(parser.usage);
    return 0;
  }
  // --goal and --tools are functionally required (declared optional in
  // argparse so --help can bypass them).
  final String? goal = r['goal'] as String?;
  if (goal == null || goal.isEmpty) {
    stderr.writeln('missing required --goal');
    return 3;
  }
  final String? rawTools = r['tools'] as String?;
  if (rawTools == null || rawTools.isEmpty) {
    stderr.writeln('missing required --tools');
    return 3;
  }
  final String? endpoint = (r['endpoint'] as String?) ??
      Platform.environment['SWIFT_INFER_ENDPOINT'];
  final String? token = (r['token'] as String?) ??
      Platform.environment['SWIFT_INFER_AGENT_TOKEN'];
  if (endpoint == null || endpoint.isEmpty) {
    stderr.writeln('missing --endpoint or SWIFT_INFER_ENDPOINT');
    return 3;
  }
  if (token == null || token.isEmpty) {
    stderr.writeln('missing --token or SWIFT_INFER_AGENT_TOKEN');
    return 3;
  }
  // Validate --tools entries contain a `.` separator before forking
  // into the runner — surface the error path 3 directly here.
  final List<String> toolNames =
      rawTools.split(',').map((String s) => s.trim()).toList();
  for (final String t in toolNames) {
    if (!t.contains('.')) {
      stderr.writeln('invalid tool name (missing namespace): $t');
      return 3;
    }
  }
  // Validate --observation-fixture exists before forking.
  final String? fixturePath = r['observation-fixture'] as String?;
  if (fixturePath != null && !await File(fixturePath).exists()) {
    stderr.writeln('observation fixture not found: $fixturePath');
    return 3;
  }
  final int maxTurns;
  final int maxTurnBudgetMs;
  try {
    maxTurns = int.parse(r['max-turns'] as String);
    maxTurnBudgetMs = int.parse(r['max-turn-budget-ms'] as String);
  } on FormatException catch (e) {
    stderr.writeln('numeric flag parse error: ${e.message}');
    return 3;
  }
  if (maxTurns <= 0 || maxTurnBudgetMs <= 0) {
    stderr.writeln('--max-turns and --max-turn-budget-ms must be positive');
    return 3;
  }
  final String tracePath = (r['trace-out'] as String?) ??
      '/tmp/agent-dogfood-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.jsonl';
  final Map<String, Object?> argsJson = <String, Object?>{
    'goal': goal,
    'tools': toolNames,
    'endpoint': endpoint,
    'token': token,
    'model': r['model'] as String,
    'observation_fixture': fixturePath,
    'max_turns': maxTurns,
    'max_turn_budget_ms': maxTurnBudgetMs,
    'verbose': r['verbose'] as bool,
    'trace_out': tracePath,
  };

  // Fork `flutter test` against the runner file. The runner reads its
  // configuration from --dart-define=DOGFOOD_ARGS_JSON and writes its
  // outcome (exit code) to --dart-define=DOGFOOD_RESULT_PATH for us to
  // recover after `flutter test` exits.
  final Directory tmp = await Directory.systemTemp.createTemp('dogfood-');
  final String resultPath = '${tmp.path}/result.json';
  final String runnerPath =
      'packages/exploration_agent/tool/agent_dogfood_runner.dart';
  final ProcessResult result = await Process.run(
    'flutter',
    <String>[
      'test',
      '--reporter',
      'expanded',
      runnerPath,
      '--dart-define=DOGFOOD_ARGS_JSON=${jsonEncode(argsJson)}',
      '--dart-define=DOGFOOD_RESULT_PATH=$resultPath',
    ],
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  // Recover the runner's reported outcome.
  final File resultFile = File(resultPath);
  if (!await resultFile.exists()) {
    stderr.writeln('dogfood runner did not write result file at $resultPath; '
        'flutter test exit=${result.exitCode}');
    return result.exitCode == 0 ? 1 : result.exitCode;
  }
  final Map<String, dynamic> resJson =
      jsonDecode(await resultFile.readAsString()) as Map<String, dynamic>;
  final int exitCode = (resJson['exit_code'] as num).toInt();
  await tmp.delete(recursive: true);
  return exitCode;
}
