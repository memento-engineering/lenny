/// The verdict a gate reads from one `leonard_cli` run, and the compact turn
/// digest that explains it.
///
/// Pure: no `dart:io`. `run.dart` feeds it the exit code and the trajectory's
/// typed records once the run has ended.
///
/// The rule: a run **fails** only when Leonard drove the app and the evidence
/// says the goal was not met — the budget ran out short of `core.done`, the
/// app's VM service went away mid-drive, or a captured frame missed its
/// golden. Every outcome that kept Leonard from forming a judgement about the
/// app (no attach, a provider that is misconfigured, unreachable or too slow,
/// a model that could not produce a valid action, a rejected observation
/// envelope, an unclassified harness exception) is **infra**, so a gate
/// re-runs it rather than sending a coding agent to fix an app that may not be
/// broken.
library;

import 'dart:convert' show utf8;

import 'package:leonard_agent/leonard_agent.dart'
    show SessionFooter, SessionOutcome, TurnRecord;

/// What a run says about the app it drove.
enum RunVerdict {
  /// The model reached the goal and called `core.done`.
  pass,

  /// The app was driven and did not reach the goal.
  fail,

  /// No judgement about the app: the harness, target or model was not usable.
  infra,
}

/// Exit codes for `--gate-exit-codes`: 0 pass, 1 fail, and 75 (`EX_TEMPFAIL`)
/// for infra, the code Gas City reserves for a check that could not reach its
/// infrastructure.
extension RunVerdictExitCode on RunVerdict {
  /// The gate exit code for this verdict.
  int get gateExitCode => switch (this) {
    RunVerdict.pass => 0,
    RunVerdict.fail => 1,
    RunVerdict.infra => 75,
  };
}

/// A [RunVerdict] and the one-line reason behind it.
typedef RunJudgement = ({RunVerdict verdict, String reason});

/// Judges a run from its process [exitCode], its trajectory [footer] (null
/// when the run ended before writing one) and its [turns].
///
/// The exit code still matters on a `done` footer: an image-golden mismatch
/// leaves the footer at `done` and exits 1, and goldens that could not be
/// compared at all (any other nonzero exit) leave the app unjudged.
RunJudgement judgeRun({
  required int exitCode,
  required SessionFooter? footer,
  required List<TurnRecord> turns,
}) {
  if (footer == null) {
    return (
      verdict: RunVerdict.infra,
      reason: exitCode == 64
          ? 'usage error: the run never started'
          : 'the run ended before writing a trajectory footer '
                '(exit $exitCode)',
    );
  }
  final String? detail = footer.terminationDetail;
  final String detailSuffix = detail == null ? '' : ' ($detail)';
  switch (footer.outcome) {
    case SessionOutcome.done:
      if (exitCode == 1) {
        return (
          verdict: RunVerdict.fail,
          reason: 'goal reached, but a captured frame did not match its golden',
        );
      }
      if (exitCode != 0) {
        return (
          verdict: RunVerdict.infra,
          reason:
              'goal reached, but the goldens could not be compared '
              '(exit $exitCode)',
        );
      }
      final String? doneReason = _doneReason(turns);
      return (
        verdict: RunVerdict.pass,
        reason: doneReason == null
            ? 'goal reached in ${footer.totalTurns} turns'
            : 'goal reached in ${footer.totalTurns} turns: $doneReason',
      );
    case SessionOutcome.budgetExhausted:
      if (detail == 'inference_latency') {
        return (
          verdict: RunVerdict.infra,
          reason:
              'the model timed out on consecutive turns (inference_latency)',
        );
      }
      return (
        verdict: RunVerdict.fail,
        reason:
            'budget exhausted after ${footer.totalTurns} turns without '
            'reaching the goal$detailSuffix',
      );
    case SessionOutcome.harnessError:
      final String code = footer.harnessError ?? 'unclassified';
      if (code == 'connection_lost' && footer.totalTurns > 0) {
        return (
          verdict: RunVerdict.fail,
          reason:
              'the app\'s VM service went away after ${footer.totalTurns} '
              'turns (did the app crash?)$detailSuffix',
        );
      }
      final String what = switch (code) {
        'connection_lost' => 'could not launch or attach to the app',
        'config_error' => 'the model provider is not configured',
        'agent_stuck' => 'the model could not produce a valid action',
        'observation_envelope_rejected' =>
          'the app\'s observation was not a valid envelope',
        _ => 'the harness ended on an unexpected error',
      };
      return (verdict: RunVerdict.infra, reason: '$what [$code]$detailSuffix');
  }
}

/// The `reason` argument of the final `core.done`, when the run ended on one.
String? _doneReason(List<TurnRecord> turns) {
  if (turns.isEmpty) return null;
  final Map<String, dynamic> action = turns.last.executedAction;
  if (action['tool'] != 'core.done') return null;
  final Object? args = action['args'];
  final Object? reason = args is Map ? args['reason'] : null;
  return reason is String && reason.trim().isNotEmpty ? reason.trim() : null;
}

/// Longest digest line, in characters.
const int kDigestLineLimit = 200;

/// Default digest budget, in UTF-8 bytes. Gas City keeps the first 4096 bytes
/// of a check script's stderr as repair context; this leaves room for the
/// verdict line.
const int kDigestByteBudget = 3000;

/// A compact, newest-last digest of [turns]: one line per turn naming the
/// action and its result, with the model's rationale on the final turn.
///
/// When the lines, newline-joined, do not fit in [byteBudget] UTF-8 bytes,
/// the oldest turns are dropped and the first line says how many, within the
/// same budget — the turns nearest the end of the run are the ones that
/// explain it, and a byte cap downstream would cut the end first.
List<String> digestTurns(
  List<TurnRecord> turns, {
  int byteBudget = kDigestByteBudget,
}) {
  final List<String> lines = <String>[
    for (var i = 0; i < turns.length; i++)
      _clip(_digestLine(turns[i], isLast: i == turns.length - 1)),
  ];
  int cost(String line) => utf8.encode(line).length + 1;
  String omitted(int count) => '… $count earlier turns omitted';
  var used = 0;
  var keepFrom = lines.length;
  while (keepFrom > 0 && used + cost(lines[keepFrom - 1]) <= byteBudget) {
    keepFrom--;
    used += cost(lines[keepFrom]);
  }
  if (keepFrom == 0) return lines;
  while (keepFrom < lines.length &&
      used + cost(omitted(keepFrom)) > byteBudget) {
    used -= cost(lines[keepFrom]);
    keepFrom++;
  }
  return <String>[omitted(keepFrom), ...lines.sublist(keepFrom)];
}

String _digestLine(TurnRecord turn, {required bool isLast}) {
  final StringBuffer line = StringBuffer('#${turn.index} ');
  final Map<String, dynamic> action = turn.executedAction;
  final Object? tool = action['tool'];
  if (tool is! String) {
    final Object? reason = turn.validation['reason'];
    line.write('no action (${reason ?? 'invalid'})');
    return line.toString();
  }
  line.write(tool);
  final Object? args = action['args'];
  if (args is Map && args.isNotEmpty) {
    // Only core tools target `core.nodes` ids; another namespace's node_id
    // would name the wrong node.
    final bool namesNodes = tool.startsWith('core.');
    String argument(Object? key, Object? value) {
      final String text = '$key=${_compact(value)}';
      final String? name = namesNodes && key == 'node_id'
          ? _nodeName(turn.observation, value)
          : null;
      return name == null ? text : '$text ($name)';
    }

    line.write(' ');
    line.write(
      <String>[
        for (final MapEntry<Object?, Object?> e in args.entries)
          argument(e.key, e.value),
      ].join(' '),
    );
  }
  final Object? result = action['result'];
  final Object? ok = result is Map ? result['ok'] : null;
  if (ok == false) {
    final Object? error = (result as Map)['error'];
    line.write(' → error: ${_compact(error ?? 'unknown')}');
  } else {
    line.write(' → ok');
  }
  final Object? rationale = turn.modelMetadata['rationale'];
  if (isLast && rationale is String && rationale.trim().isNotEmpty) {
    line.write(' — ${rationale.trim()}');
  }
  return line.toString();
}

/// The label of the node [nodeId] names in [observation]'s `core.nodes`, or
/// its value when it has no label; null when the observation does not hold
/// the node or the node has neither. Whitespace runs collapse to one space.
String? _nodeName(Map<String, dynamic> observation, Object? nodeId) {
  if (nodeId is! int && nodeId is! String) return null;
  final Object? core = observation['core'];
  if (core is! Map) return null;
  final Object? nodes = core['nodes'];
  if (nodes is! Map) return null;
  final Object? node = nodes['$nodeId'];
  if (node is! Map) return null;
  String? named(Object? text) {
    if (text is! String) return null;
    final String collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? null : collapsed;
  }

  return named(node['label']) ?? named(node['value']);
}

String _compact(Object? value) {
  final String text = value is String ? '"$value"' : '$value';
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

String _clip(String line) => line.length <= kDigestLineLimit
    ? line
    : '${line.substring(0, kDigestLineLimit - 1)}…';
