library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/verify_mutation_rebaseline.dart'
    show maximumSurvivors, maximumSurvivorsPerFile;

void main() {
  final Directory packageRoot = _packageRoot();
  final File checkedIn = File(
    '${packageRoot.path}/test/tool/fixtures/mutation-report.json',
  );
  late Directory reports;

  setUp(() {
    reports = Directory.systemTemp.createTempSync('mutation-rebaseline-');
  });

  tearDown(() {
    reports.deleteSync(recursive: true);
  });

  Future<ProcessResult> verify([List<String>? arguments]) => Process.run(
    'dart',
    <String>['run', 'tool/verify_mutation_rebaseline.dart', ...?arguments],
    workingDirectory: packageRoot.path,
  );

  /// The checked-in fixture, decoded so a case can move one file's mutants.
  Map<String, Object?> fixture() =>
      jsonDecode(checkedIn.readAsStringSync()) as Map<String, Object?>;

  void write(Map<String, Object?> document) => File(
    '${reports.path}/mutation-report.json',
  ).writeAsStringSync(jsonEncode(document));

  /// Replaces [file]'s mutants with [survivors] survivors and one kill.
  void setSurvivors(Map<String, Object?> document, String file, int survivors) {
    final Map<String, Object?> files =
        document['files']! as Map<String, Object?>;
    (files[file]! as Map<String, Object?>)['mutants'] = <Map<String, Object?>>[
      for (var index = 0; index <= survivors; index++)
        <String, Object?>{
          'id': '$file:$index',
          'mutatorName': 'equality',
          'location': <String, Object?>{
            'start': <String, Object?>{'line': index + 1, 'column': 3},
            'end': <String, Object?>{'line': index + 1, 'column': 9},
          },
          'status': index < survivors ? 'Survived' : 'Killed',
          'replacement': '!=',
        },
    ];
  }

  test(
    'accepts the checked-in report and prints the audited receipt',
    () async {
      checkedIn.copySync('${reports.path}/mutation-report.json');

      final ProcessResult result = await verify(<String>[reports.path]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout.toString().trim(),
        'MUTATION_REBASELINE PASS: 10 mutants across 2 files, 5 killed, '
        '3 survived (budget $maximumSurvivors), 1 uncovered, 1 not compiling; '
        'MSI 55.56%, covered-code MSI 62.50%; worst file lib/src/beta.dart '
        'with 2 survivors (budget $maximumSurvivorsPerFile).',
      );
    },
  );

  test('reds when one file exceeds the per-file survivor budget', () async {
    final Map<String, Object?> document = fixture();
    setSurvivors(document, 'lib/src/beta.dart', maximumSurvivorsPerFile);
    write(document);
    expect(
      (await verify(<String>[reports.path])).exitCode,
      0,
      reason: 'the budget itself is still a pass',
    );

    setSurvivors(document, 'lib/src/beta.dart', maximumSurvivorsPerFile + 1);
    write(document);

    final ProcessResult result = await verify(<String>[reports.path]);

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains(
        'lib/src/beta.dart has ${maximumSurvivorsPerFile + 1} survivors',
      ),
    );
    expect(result.stderr, isNot(contains('lib/src/alpha.dart')));
  });

  test('reds when the package total exceeds its budget', () async {
    final Map<String, Object?> document = fixture();
    // Two files, each inside the per-file budget, whose sum is not: the total
    // budget has to be its own check.
    setSurvivors(document, 'lib/src/alpha.dart', maximumSurvivorsPerFile);
    setSurvivors(
      document,
      'lib/src/beta.dart',
      maximumSurvivors - maximumSurvivorsPerFile + 1,
    );
    write(document);

    final ProcessResult result = await verify(<String>[reports.path]);

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('${maximumSurvivors + 1} survivors across the package'),
    );
  });

  test('uses exit 64 for wrong arity', () async {
    expect((await verify()).exitCode, 64);
    expect((await verify(<String>[reports.path, reports.path])).exitCode, 64);
  });

  test('uses exit 66 for absent, malformed and empty reports', () async {
    expect((await verify(<String>[reports.path])).exitCode, 66);

    File('${reports.path}/mutation-report.json').writeAsStringSync('{');
    expect((await verify(<String>[reports.path])).exitCode, 66);

    write(<String, Object?>{'schemaVersion': '1'});
    ProcessResult result = await verify(<String>[reports.path]);
    expect(result.exitCode, 66);
    expect(result.stderr, contains('no per-file map'));

    write(<String, Object?>{'files': <String, Object?>{}});
    expect((await verify(<String>[reports.path])).exitCode, 66);

    final Map<String, Object?> unknown = fixture();
    ((((unknown['files']! as Map<String, Object?>)['lib/src/beta.dart']!
                        as Map<String, Object?>)['mutants']!
                    as List<Object?>)
                .first!
            as Map<String, Object?>)['status'] =
        'Pulverised';
    write(unknown);
    result = await verify(<String>[reports.path]);
    expect(result.exitCode, 66);
    expect(result.stderr, contains('unknown mutant status'));
  });

  test('the checked-in fixture is a report, not a transcript', () {
    final Map<String, Object?> document = fixture();
    expect(document['schemaVersion'], '1');
    final Map<String, Object?> files =
        document['files']! as Map<String, Object?>;
    expect(files.keys, <String>['lib/src/alpha.dart', 'lib/src/beta.dart']);
    for (final Object? file in files.values) {
      expect((file! as Map<String, Object?>)['source'], isA<String>());
      expect((file as Map<String, Object?>)['mutants'], isA<List<Object?>>());
    }
  });
}

Directory _packageRoot() {
  Directory current = Directory.current.absolute;
  while (!File('${current.path}/pubspec.yaml').existsSync() ||
      !Directory('${current.path}/lib').existsSync()) {
    if (current.parent.path == current.path) {
      throw StateError('package root not found');
    }
    current = current.parent;
  }
  return current;
}
