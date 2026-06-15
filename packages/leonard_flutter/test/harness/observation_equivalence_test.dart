library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_flutter/test_support/observation_equivalence.dart';
import 'package:flutter_test/flutter_test.dart';

File _goldenFile(String name) {
  const String relativePath = 'test/goldens';
  for (final String prefix in <String>['', 'packages/leonard_flutter/']) {
    final File f = File('$prefix$relativePath/$name.observation.json');
    if (f.existsSync()) return f;
  }
  throw FileSystemException(
    'Cannot locate golden fixture — run from package or workspace root',
    '$relativePath/$name.observation.json',
  );
}

Map<String, Object?> _loadGolden(String name) {
  return (jsonDecode(_goldenFile(name).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

void main() {
  group('assertObservationEquivalent', () {
    for (final String name in <String>['core', 'dio', 'riverpod', 'router']) {
      test('$name golden is self-equivalent', () {
        final Map<String, Object?> golden = _loadGolden(name);
        assertObservationEquivalent(golden, golden);
      });
    }

    test('detects different semantics list', () {
      final Map<String, Object?> base = _loadGolden('core');
      final Map<String, Object?> diverged = Map<String, Object?>.from(base)
        ..['semantics'] = <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'role': 'button',
            'label': 'Sign in',
            'rect': <int>[0, 0, 120, 48],
          },
        ];
      expect(
        () => assertObservationEquivalent(base, diverged),
        throwsA(isA<TestFailure>()),
      );
    });

    test('detects different routes', () {
      final Map<String, Object?> base = _loadGolden('core');
      final Map<String, Object?> diverged = Map<String, Object?>.from(base)
        ..['routes'] = <String>['home'];
      expect(
        () => assertObservationEquivalent(base, diverged),
        throwsA(isA<TestFailure>()),
      );
    });

    test('detects divergent extension fragment', () {
      final Map<String, Object?> base = _loadGolden('dio');
      final Map<String, Object?> diverged = Map<String, Object?>.from(base)
        ..['extensions'] = <String, Object?>{
          'dio': <String, Object?>{
            'in_flight': <Object?>[],
            'recent_completed': <Object?>[],
          },
        };
      expect(
        () => assertObservationEquivalent(base, diverged),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
