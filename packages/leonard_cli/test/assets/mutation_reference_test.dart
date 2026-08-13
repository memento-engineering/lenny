library;

import 'package:test/test.dart';

import '../support/vended_assets.dart';

void main() {
  final String reference = vendedMarkdown().entries
      .singleWhere(
        (MapEntry<String, String> entry) =>
            entry.key.endsWith('test-with-leonard/references/mutation.md'),
      )
      .value;

  test('starts every assertion review with a named breaking change', () {
    expect(
      reference,
      contains(
        'Before writing an assertion, name the single-line source change '
        'that would make the test fail.',
      ),
    );
    expect(reference, contains('the assertion is decorative'));
    expect(reference, contains('could a wrong output still produce'));
  });

  test('carries every calibrated failure mode and its Leonard evidence', () {
    for (final String evidence in <String>[
      'Contract-facing text is behaviour',
      'Protocol constants are behaviour',
      'A shipped test double is public API',
      'Probe asymmetry',
      '`throwsX` proves a throw type, not a diagnosis',
      'validator and coercer branch',
      'Drive testability seams',
      'class documentation as a test checklist',
      'consumer is tolerant',
      'lenny-i2j6',
      'lenny-tkr2',
      'lenny-s4mb',
    ]) {
      expect(reference, contains(evidence), reason: evidence);
    }
  });

  test('requires evidence before exclusions and before bug-fix claims', () {
    expect(reference, contains('Verify before excluding'));
    expect(reference, contains('Essential equivalence'));
    expect(reference, contains('Incidental equivalence'));
    expect(reference, contains('Read results per file'));
    expect(
      reference,
      contains('fails on the parent commit and passes on the fix'),
    );
  });

  test('reports measured calibration, including contradiction and uplift', () {
    for (final String receipt in <String>[
      '542 mutants, 215 survivors, 60.33% killed',
      '49.09% killed',
      '54/55 killed, 98.18%',
      '126 of 777 mutants',
      '77.78%',
      'Three of five predictions were wrong',
      '13/13',
      '8/8',
      '5/5',
    ]) {
      expect(reference, contains(receipt), reason: receipt);
    }
  });
}
