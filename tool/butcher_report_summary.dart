import 'dart:convert';
import 'dart:io';

/// Reduces butcher's Stryker JSON report to counts a shell can read.
///
/// The positional interface is:
///
///     dart run tool/butcher_report_summary.dart REPORT [--markdown PATH]
///
/// stdout is one `key=value` line per count, so a caller sizes a run, gates on
/// a score, or sums shards without parsing JSON itself. `--markdown` also
/// renders the surviving mutants, one section per file, which is the human
/// half of the same document.
///
/// This is the only reader of the report's shape on the pure-Dart mutation
/// path: the runner sizes its dry phase from `mutants`, and the shard
/// aggregator sums these lines.
void main(List<String> arguments) {
  try {
    stdout.write(_summarize(arguments));
  } on _CliFailure catch (failure) {
    stderr.writeln('error: ${failure.message}');
    exitCode = failure.code;
  }
}

/// The eight statuses of the report schema, in the order they are printed.
const Map<String, String> _statusKeys = <String, String>{
  'Killed': 'killed',
  'Survived': 'survived',
  'NoCoverage': 'no_coverage',
  'CompileError': 'compile_error',
  'RuntimeError': 'runtime_error',
  'Timeout': 'timeout',
  'Ignored': 'ignored',
  'Pending': 'pending',
};

String _summarize(List<String> arguments) {
  String? markdownPath;
  final List<String> positional = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    if (arguments[index] == '--markdown') {
      if (index + 1 >= arguments.length) {
        throw const _CliFailure(64, '--markdown requires a path');
      }
      markdownPath = arguments[++index];
      continue;
    }
    positional.add(arguments[index]);
  }
  if (positional.length != 1) {
    throw const _CliFailure(
      64,
      'usage: butcher_report_summary.dart REPORT [--markdown PATH]',
    );
  }

  final File report = File(positional.single);
  if (!report.existsSync()) {
    throw _CliFailure(66, 'report not found: ${report.path}');
  }
  final Map<String, Map<String, Object?>> files = _files(report);

  final Map<String, int> counts = <String, int>{
    for (final String key in _statusKeys.values) key: 0,
  };
  final Map<String, List<Map<String, Object?>>> survivors =
      <String, List<Map<String, Object?>>>{};
  var mutants = 0;
  for (final MapEntry<String, Map<String, Object?>> file in files.entries) {
    for (final Map<String, Object?> mutant in _mutants(file)) {
      mutants++;
      final Object? status = mutant['status'];
      if (status is! String || !_statusKeys.containsKey(status)) {
        throw _CliFailure(66, 'unknown mutant status in ${file.key}: $status');
      }
      counts[_statusKeys[status]!] = counts[_statusKeys[status]!]! + 1;
      if (status == 'Survived') {
        survivors
            .putIfAbsent(file.key, () => <Map<String, Object?>>[])
            .add(mutant);
      }
    }
  }

  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(_markdown(survivors));
  }

  // Timeouts are inconclusive and sit in neither score term, so they are
  // counted and reported but never scored (butcher ADR 0013).
  final int killed = counts['killed']!;
  final int scoreable = killed + counts['survived']! + counts['no_coverage']!;
  final int covered = killed + counts['survived']!;
  final StringBuffer out = StringBuffer('mutants=$mutants\n');
  for (final String key in _statusKeys.values) {
    out.writeln('$key=${counts[key]}');
  }
  return (out
        ..writeln('msi=${_percentage(killed, scoreable)}')
        ..writeln('covered_msi=${_percentage(killed, covered)}'))
      .toString();
}

String _percentage(int part, int whole) =>
    whole == 0 ? 'none' : (100 * part / whole).toStringAsFixed(2);

Map<String, Map<String, Object?>> _files(File report) {
  final Object? document;
  try {
    document = jsonDecode(report.readAsStringSync());
  } on FormatException catch (error) {
    throw _CliFailure(66, 'malformed report ${report.path}: ${error.message}');
  }
  if (document is! Map<String, Object?>) {
    throw _CliFailure(66, 'report is not an object: ${report.path}');
  }
  final Object? files = document['files'];
  if (files is! Map<String, Object?>) {
    throw _CliFailure(66, 'report has no files map: ${report.path}');
  }
  return <String, Map<String, Object?>>{
    for (final MapEntry<String, Object?> file in files.entries)
      file.key: file.value is Map<String, Object?>
          ? file.value! as Map<String, Object?>
          : throw _CliFailure(66, 'report entry is not an object: ${file.key}'),
  };
}

Iterable<Map<String, Object?>> _mutants(
  MapEntry<String, Map<String, Object?>> file,
) {
  final Object? mutants = file.value['mutants'];
  if (mutants is! List<Object?>) {
    throw _CliFailure(66, 'report file has no mutants list: ${file.key}');
  }
  return mutants.map((Object? mutant) {
    if (mutant is! Map<String, Object?>) {
      throw _CliFailure(66, 'report mutant is not an object: ${file.key}');
    }
    return mutant;
  });
}

String _markdown(Map<String, List<Map<String, Object?>>> survivors) {
  final StringBuffer document = StringBuffer('# Mutation report\n');
  for (final String file in survivors.keys.toList()..sort()) {
    document.writeln('\n## Surviving mutants in $file\n');
    for (final Map<String, Object?> mutant in survivors[file]!) {
      document.writeln(
        '- ${_location(mutant)} ${mutant['mutatorName']}: '
        '${_inline(mutant['replacement'])}',
      );
    }
  }
  return document.toString();
}

String _location(Map<String, Object?> mutant) {
  final Object? location = mutant['location'];
  if (location is! Map<String, Object?>) {
    return '?:?';
  }
  final Object? start = location['start'];
  if (start is! Map<String, Object?>) {
    return '?:?';
  }
  return '${start['line']}:${start['column']}';
}

String _inline(Object? replacement) {
  final String text = '$replacement'.replaceAll('\n', ' ');
  return '`${text.replaceAll('`', "'")}`';
}

class _CliFailure implements Exception {
  const _CliFailure(this.code, this.message);

  final int code;
  final String message;
}
