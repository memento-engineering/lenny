library;

import 'package:flutter_test/flutter_test.dart';

void assertObservationEquivalent(
  Map<String, Object?> legacy,
  Map<String, Object?> perception,
) {
  for (final field in const <String>[
    'semantics',
    'routes',
    'errors',
    'stability',
  ]) {
    expect(
      perception[field],
      equals(legacy[field]),
      reason:
          'observation field "$field" must match between '
          'legacy and perception paths',
    );
  }
  final legacyExtensions =
      (legacy['extensions'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  final perceptionExtensions =
      (perception['extensions'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  for (final ns in legacyExtensions.keys) {
    expect(
      perceptionExtensions[ns],
      equals(legacyExtensions[ns]),
      reason:
          'plugin "$ns" fragment must match between '
          'legacy and perception paths',
    );
  }
}
