library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final Directory packageRoot = _packageRoot();
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

  test(
    'accepts a code-operator survivor and prints the audited receipt',
    () async {
      _writeReports(
        reports,
        total: 10,
        undetected: 1,
        rating: 'B',
        survivors: const <_Mutation>[
          _Mutation(
            'final result = left - right;',
            'final result = left + right;',
          ),
        ],
      );

      final ProcessResult result = await verify(<String>[reports.path]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout.toString().trim(),
        'MUTATION_REBASELINE PASS: 10 mutants, 1 undetected, 90.00% '
        'killed, rating B; 0 string-interior survivors; 2026-08-01 '
        '542/215/60.33%/C is not comparable (string exclusion disabled); '
        'mutation_test 1.8.0 compile-error inflation remains.',
      );
    },
  );

  test('rejects survivors inside every supported string delimiter', () async {
    final List<String> originals = <String>[
      "final value = 'element-type';",
      'final value = "element-type";',
      "final value = '''element-type''';",
      'final value = """element-type""";',
      "final value = r'element-type';",
      'final value = R"element-type";',
      "final value = r'''element-type''';",
      'final value = R"""element-type""";',
      r"final value = 'element\'-type';",
      "final value = <String, String>{'element-type': 'value'};",
      r"final value = 'element-type $suffix';",
      r"final value = '${2 - 1}';",
    ];
    _writeReports(
      reports,
      total: 20,
      undetected: originals.length,
      rating: 'D',
      survivors: originals
          .map(
            (String original) =>
                _Mutation(original, original.replaceFirst('-', '+')),
          )
          .toList(),
    );

    final ProcessResult result = await verify(<String>[reports.path]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('12 string-interior survivors remain'));
  });

  test('rejects the 215-undetected boundary', () async {
    final List<_Mutation> survivors = List<_Mutation>.generate(215, (int i) {
      return _Mutation('final value$i = $i - 1;', 'final value$i = $i + 1;');
    });
    _writeReports(
      reports,
      total: 300,
      undetected: survivors.length,
      rating: 'D',
      survivors: survivors,
    );

    final ProcessResult result = await verify(<String>[reports.path]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('expected fewer than 215'));
    expect(result.stderr, isNot(contains('XML has')));
  });

  test('rejects XML and Markdown survivor-count disagreement', () async {
    _writeReports(
      reports,
      total: 10,
      undetected: 2,
      rating: 'C',
      survivors: const <_Mutation>[
        _Mutation('final value = 2 - 1;', 'final value = 2 + 1;'),
      ],
    );

    final ProcessResult result = await verify(<String>[reports.path]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('XML has 1 survivors'));
  });

  test('uses exit 64 for wrong arity', () async {
    expect((await verify()).exitCode, 64);
    expect((await verify(<String>[reports.path, reports.path])).exitCode, 64);
  });

  test('uses exit 66 for absent and malformed reports', () async {
    expect((await verify(<String>[reports.path])).exitCode, 66);

    _writeReports(
      reports,
      total: 10,
      undetected: 1,
      rating: 'B',
      survivors: const <_Mutation>[
        _Mutation('final value = 2 - 1;', 'final value = 2 + 1;'),
      ],
    );
    File('${reports.path}/mutation-test-report.xml').writeAsStringSync('<');
    expect((await verify(<String>[reports.path])).exitCode, 66);

    _writeReports(
      reports,
      total: 10,
      undetected: 1,
      rating: 'B',
      survivors: const <_Mutation>[
        _Mutation('final value = 2 - 1;', 'final value = 2 + 1;'),
      ],
    );
    File(
      '${reports.path}/mutation-test-report.md',
    ).writeAsStringSync('| Mutations | not-a-number |\n');
    expect((await verify(<String>[reports.path])).exitCode, 66);
  });
}

void _writeReports(
  Directory directory, {
  required int total,
  required int undetected,
  required String rating,
  required List<_Mutation> survivors,
}) {
  final String undetectedPercentage = (100 * undetected / total)
      .toStringAsFixed(2);
  File('${directory.path}/mutation-test-report.md').writeAsStringSync('''
# Mutation report

| Key | Value |
| --- | --- |
| Mutations | $total |
| Undetected | $undetected |
| Undetected% | $undetectedPercentage% |
| Quality Rating | $rating |
''');

  final StringBuffer xml = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<undetected-mutations>\n'
    '<file name="lib/example.dart">\n',
  );
  for (var index = 0; index < survivors.length; index++) {
    final _Mutation survivor = survivors[index];
    xml
      ..writeln('<mutation line="${index + 1}">')
      ..writeln('<original>${_escapeXml(survivor.original)}</original>')
      ..writeln('<modified>${_escapeXml(survivor.modified)}</modified>')
      ..writeln('</mutation>');
  }
  xml.write('</file>\n</undetected-mutations>\n');
  File(
    '${directory.path}/mutation-test-report.xml',
  ).writeAsStringSync(xml.toString());
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

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

class _Mutation {
  const _Mutation(this.original, this.modified);

  final String original;
  final String modified;
}
