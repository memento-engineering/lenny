import 'dart:convert';
import 'dart:io';

/// Survivors this package is allowed in total before the score has regressed.
///
/// Set from the 2026-09-24 cut-over run on butcher: 663 mutants, 101
/// survivors. A rebaseline moves this number and says why in the same change.
const int maximumSurvivors = 101;

/// Survivors any single file is allowed.
///
/// Set from the worst file of the same run, `lib/src/xcuitest_backend.dart`
/// with 31. A per-file budget is what makes the check sensitive: a total
/// budget alone lets one file rot behind another file's improvement.
const int maximumSurvivorsPerFile = 31;

/// Verifies a full mutation report against this package's survivor budgets.
///
/// Reads the Stryker JSON document butcher writes and works from its per-file
/// map, so the numbers are per file rather than one package total.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tool/verify_mutation_rebaseline.dart REPORT_DIRECTORY',
    );
    exitCode = 64;
    return;
  }

  try {
    final Map<String, _FileScore> perFile = _parse(
      File('${arguments.single}/mutation-report.json').readAsStringSync(),
    );
    final _FileScore total = perFile.values.fold(
      const _FileScore(),
      (_FileScore sum, _FileScore file) => sum + file,
    );
    if (total.mutants == 0) {
      throw const FormatException('the report contains no mutants');
    }

    final List<String> failures = <String>[];
    if (total.survived > maximumSurvivors) {
      failures.add(
        '${total.survived} survivors across the package; '
        'the budget is $maximumSurvivors',
      );
    }
    final List<String> overBudget =
        perFile.keys
            .where(
              (String file) =>
                  perFile[file]!.survived > maximumSurvivorsPerFile,
            )
            .toList()
          ..sort();
    for (final String file in overBudget) {
      failures.add(
        '$file has ${perFile[file]!.survived} survivors; '
        'the per-file budget is $maximumSurvivorsPerFile',
      );
    }

    if (failures.isNotEmpty) {
      stderr.writeln('MUTATION_REBASELINE FAIL: ${failures.join('; ')}');
      exitCode = 1;
      return;
    }

    final MapEntry<String, _FileScore> worst = perFile.entries.reduce(
      (MapEntry<String, _FileScore> a, MapEntry<String, _FileScore> b) =>
          b.value.survived > a.value.survived ? b : a,
    );
    stdout.writeln(
      'MUTATION_REBASELINE PASS: ${total.mutants} mutants across '
      '${perFile.length} files, ${total.killed} killed, '
      '${total.survived} survived (budget $maximumSurvivors), '
      '${total.uncovered} uncovered, ${total.compileErrors} not compiling; '
      'MSI ${_percentage(total.killed, total.scoreable)}, covered-code MSI '
      '${_percentage(total.killed, total.covered)}; worst file '
      '${worst.key} with ${worst.value.survived} survivors '
      '(budget $maximumSurvivorsPerFile).',
    );
  } on FileSystemException catch (error) {
    stderr.writeln('mutation report unavailable: ${error.message}');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('malformed mutation report: ${error.message}');
    exitCode = 66;
  }
}

String _percentage(int part, int whole) =>
    whole == 0 ? 'none' : '${(100 * part / whole).toStringAsFixed(2)}%';

Map<String, _FileScore> _parse(String document) {
  final Object? decoded = jsonDecode(document);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('the report is not an object');
  }
  final Object? files = decoded['files'];
  if (files is! Map<String, Object?>) {
    throw const FormatException('the report has no per-file map');
  }
  final Map<String, _FileScore> perFile = <String, _FileScore>{};
  for (final MapEntry<String, Object?> file in files.entries) {
    final Object? value = file.value;
    if (value is! Map<String, Object?>) {
      throw FormatException('${file.key} is not an object');
    }
    final Object? mutants = value['mutants'];
    if (mutants is! List<Object?>) {
      throw FormatException('${file.key} has no mutants list');
    }
    var score = const _FileScore();
    for (final Object? mutant in mutants) {
      if (mutant is! Map<String, Object?>) {
        throw FormatException('${file.key} has a mutant that is not an object');
      }
      score += _FileScore.ofStatus(mutant['status']);
    }
    perFile[file.key] = score;
  }
  if (perFile.isEmpty) {
    throw const FormatException('the per-file map is empty');
  }
  return perFile;
}

/// One file's mutant counts, or a sum of several files'.
class _FileScore {
  const _FileScore({
    this.mutants = 0,
    this.killed = 0,
    this.survived = 0,
    this.uncovered = 0,
    this.compileErrors = 0,
  });

  /// The counts contributed by one mutant with [status].
  factory _FileScore.ofStatus(Object? status) {
    switch (status) {
      case 'Killed':
        return const _FileScore(mutants: 1, killed: 1);
      case 'Survived':
        return const _FileScore(mutants: 1, survived: 1);
      case 'NoCoverage':
        return const _FileScore(mutants: 1, uncovered: 1);
      case 'CompileError':
        return const _FileScore(mutants: 1, compileErrors: 1);
      case 'RuntimeError':
      case 'Timeout':
      case 'Ignored':
      case 'Pending':
        return const _FileScore(mutants: 1);
      default:
        throw FormatException('unknown mutant status: $status');
    }
  }

  final int mutants;
  final int killed;
  final int survived;
  final int uncovered;
  final int compileErrors;

  /// Killed, survived and uncovered: the mutation score's denominator.
  int get scoreable => killed + survived + uncovered;

  /// Killed and survived: the covered-code score's denominator.
  int get covered => killed + survived;

  _FileScore operator +(_FileScore other) => _FileScore(
    mutants: mutants + other.mutants,
    killed: killed + other.killed,
    survived: survived + other.survived,
    uncovered: uncovered + other.uncovered,
    compileErrors: compileErrors + other.compileErrors,
  );
}
