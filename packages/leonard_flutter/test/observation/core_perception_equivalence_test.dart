library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_flutter/src/observation/core_fragment.dart';
import 'package:leonard_flutter/src/observation/core_perception.dart';
import 'package:leonard_flutter/src/observation/stability_metadata.dart';
import 'package:leonard_flutter/src/observation/observation_request.dart';
import 'package:leonard_flutter/src/errors/error_ring_buffer.dart';
import 'package:leonard_flutter/test_support/observation_equivalence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Dual-prefix golden resolver (mirrors
/// test/harness/observation_equivalence_test.dart) so the test passes whether
/// run from the package dir or the workspace root.
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

Map<String, Object?> _loadGolden(String name) =>
    (jsonDecode(_goldenFile(name).readAsStringSync()) as Map)
        .cast<String, Object?>();

/// Serialize the core perception fragment from a [Seed] via a throwaway
/// [PerceptionOwner], disposed in finally (mirrors dio's `_harvestFragment`).
Map<String, Object?> _harvestCoreFragment(Seed seed) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(seed);
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

/// Core lives at the response TOP LEVEL (not under `extensions`), so the
/// equivalence wrapper carries the four core keys directly and an empty
/// `extensions` map on both sides.
Map<String, Object?> _wrap(Map<String, Object?> coreFrag) => <String, Object?>{
  'semantics': coreFrag['semantics'] ?? <Object?>[],
  'routes': coreFrag['routes'] ?? <Object?>[],
  'errors': coreFrag['errors'] ?? <Object?>[],
  'stability': coreFrag['stability'] ?? <String, Object?>{},
  'extensions': <String, Object?>{},
};

void main() {
  test('golden anchor: legacy == perception == core.observation.json', () {
    // Drive BOTH paths from the golden's EXACT primitives so legacy and
    // perception are byte-identical to each other AND to the golden. The
    // golden's stability is a curated fixture
    // ({"policy":"action_relative","reason":"idle"}) that differs from a live
    // StabilityMetadata.toJson(); feeding it verbatim lets the golden
    // assertion cover all four core keys (semantics, routes, errors,
    // stability), not just three.
    final Map<String, Object?> golden = _loadGolden('core');
    final List<Map<String, Object>> semantics =
        (golden['semantics'] as List<Object?>)
            .map((Object? e) => (e as Map).cast<String, Object>())
            .toList(growable: false);
    final List<String> routes = (golden['routes'] as List<Object?>)
        .map((Object? e) => e as String)
        .toList(growable: false);
    final List<Map<String, Object?>> errors =
        (golden['errors'] as List<Object?>)
            .map((Object? e) => (e as Map).cast<String, Object?>())
            .toList(growable: false);
    final Map<String, Object?> stability = (golden['stability'] as Map)
        .cast<String, Object?>();

    final CoreFragmentValues values = CoreFragmentValues(
      semantics: semantics,
      routes: routes,
      errors: errors,
      stability: stability,
    );

    final Map<String, Object?> legacy = values.toMap();
    final Map<String, Object?> perception = _harvestCoreFragment(
      buildCorePerceptionSeed(
        semantics: semantics,
        routes: routes,
        errors: errors,
        stability: stability,
      ),
    );

    // Legacy vs perception: deep equality on the four core keys.
    assertObservationEquivalent(_wrap(legacy), _wrap(perception));

    // Lock key order: byte-identical JSON encodings.
    expect(
      jsonEncode(legacy),
      equals(jsonEncode(perception)),
      reason: 'core perception fragment must be byte-identical to legacy',
    );

    // Golden anchor: both paths reproduce every core key in the golden.
    for (final String key in const <String>[
      'semantics',
      'routes',
      'errors',
      'stability',
    ]) {
      expect(
        legacy[key],
        equals(golden[key]),
        reason: 'legacy core "$key" must match golden',
      );
      expect(
        perception[key],
        equals(golden[key]),
        reason: 'perception core "$key" must match golden',
      );
    }
  });

  test(
    'live shape: legacy map seams == perception seed (byte-equal)',
    () async {
      // Exercise the legacy map path through computeCoreFragmentValues.toMap()
      // with real seam closures, then drive the perception path from the SAME
      // computed values. This proves the dual path holds for the production
      // StabilityMetadata.toJson() shape, not just the curated golden.
      final List<Map<String, Object>> semanticsSeed = <Map<String, Object>>[
        <String, Object>{
          'id': 1,
          'role': 'button',
          'label': 'Sign in',
          'rect': <int>[0, 0, 120, 48],
        },
      ];
      Future<List<Map<String, Object>>> captureSemantics() async =>
          semanticsSeed;
      List<ErrorEntry> errorsSince(int? cursor) => <ErrorEntry>[
        ErrorEntry(
          seq: 1,
          message: 'boom',
          frames: const <String>['#0 main'],
          wallClockOffsetMs: 42,
        ),
      ];
      const StabilityMetadata stability = StabilityMetadata(
        policy: StabilityPolicy.actionRelative,
        terminatedBy: TerminatedBy.idle,
        durationMs: 17,
        frameworkBusy: <String, Object?>{'transient': 0},
        extensionsBusy: <ExtensionBusy>[],
      );
      List<String> routeStackProvider() => <String>['home'];

      // Same computed values feed both the legacy map and the perception path.
      final CoreFragmentValues values = await computeCoreFragmentValues(
        captureSemantics: captureSemantics,
        errorsSince: errorsSince,
        stability: stability,
        includeScreenshot: false,
        captureScreenshot: null,
        errorCursor: 0,
        routeStackProvider: routeStackProvider,
      );
      final Map<String, Object?> legacy = values.toMap();
      final Map<String, Object?> perception = _harvestCoreFragment(
        buildCorePerceptionSeed(
          semantics: values.semantics,
          routes: values.routes,
          errors: values.errors,
          stability: values.stability,
          screenshot: values.screenshot,
        ),
      );

      assertObservationEquivalent(_wrap(legacy), _wrap(perception));
      expect(
        jsonEncode(legacy),
        equals(jsonEncode(perception)),
        reason: 'core perception fragment must be byte-identical to legacy',
      );
    },
  );

  test(
    'screenshot field: included only when captured (collection-if omit)',
    () async {
      final List<Map<String, Object>> semanticsSeed = <Map<String, Object>>[];
      Future<List<Map<String, Object>>> captureSemantics() async =>
          semanticsSeed;
      List<ErrorEntry> errorsSince(int? cursor) => const <ErrorEntry>[];
      const StabilityMetadata stability = StabilityMetadata(
        policy: StabilityPolicy.actionRelative,
        terminatedBy: TerminatedBy.idle,
        durationMs: 0,
        frameworkBusy: <String, Object?>{},
        extensionsBusy: <ExtensionBusy>[],
      );

      // With screenshot present.
      final CoreFragmentValues valuesWith = await computeCoreFragmentValues(
        captureSemantics: captureSemantics,
        errorsSince: errorsSince,
        stability: stability,
        includeScreenshot: true,
        captureScreenshot: () async => 'AAAA',
        errorCursor: 0,
        routeStackProvider: () => const <String>[],
      );
      final Map<String, Object?> legacyWith = valuesWith.toMap();
      final Map<String, Object?> perceptionWith = _harvestCoreFragment(
        buildCorePerceptionSeed(
          semantics: valuesWith.semantics,
          routes: valuesWith.routes,
          errors: valuesWith.errors,
          stability: valuesWith.stability,
          screenshot: valuesWith.screenshot,
        ),
      );
      expect(legacyWith.containsKey('screenshot_png_b64'), isTrue);
      expect(perceptionWith.containsKey('screenshot_png_b64'), isTrue);
      expect(jsonEncode(legacyWith), equals(jsonEncode(perceptionWith)));

      // Without screenshot — the key must be ABSENT on both sides, not null.
      final CoreFragmentValues valuesWithout = await computeCoreFragmentValues(
        captureSemantics: captureSemantics,
        errorsSince: errorsSince,
        stability: stability,
        includeScreenshot: false,
        captureScreenshot: null,
        errorCursor: 0,
        routeStackProvider: () => const <String>[],
      );
      final Map<String, Object?> legacyWithout = valuesWithout.toMap();
      final Map<String, Object?> perceptionWithout = _harvestCoreFragment(
        buildCorePerceptionSeed(
          semantics: valuesWithout.semantics,
          routes: valuesWithout.routes,
          errors: valuesWithout.errors,
          stability: valuesWithout.stability,
          screenshot: valuesWithout.screenshot,
        ),
      );
      expect(legacyWithout.containsKey('screenshot_png_b64'), isFalse);
      expect(perceptionWithout.containsKey('screenshot_png_b64'), isFalse);
      expect(jsonEncode(legacyWithout), equals(jsonEncode(perceptionWithout)));
    },
  );
}
