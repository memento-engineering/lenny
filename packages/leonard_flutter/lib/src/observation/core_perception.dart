library;

import 'package:genesis_perception/genesis_perception.dart';

/// Perception-native projection of the binding-assembled core fragment
/// (PRD §9.2): `semantics`, `routes`, `errors`, `stability`, and the
/// optional `screenshot_png_b64`.
///
/// Core is NOT a registered [LeonardExtension] — its fragment must sit at
/// the response top level, not nested under `plugins.<ns>`. Therefore core
/// deliberately does NOT flow through the binding's generic plugin
/// observation loop (which emits `plugins.<ns>`). Instead the binding builds
/// the core `Seed` from [buildCorePerceptionSeed] and serializes it through
/// this dedicated perception path at the top level.
///
/// Each [Field] value is assigned verbatim by `serializePerceptionFragment`
/// (no re-serialization, no transformation), so feeding the SAME already-
/// computed primitives [CoreFragmentValues] carries yields a fragment that is
/// deep-equal AND byte-equal (key order preserved) to [CoreFragmentValues.toMap].
class CorePerception extends StatelessPerception {
  /// Captures the already-computed core primitives so the [Node] is built
  /// from the identical values [CoreFragmentValues] assembles into its map.
  const CorePerception({
    super.key,
    required this.semantics,
    required this.routes,
    required this.errors,
    required this.stability,
    this.screenshot,
  });

  /// `captureSemantics()` output, verbatim.
  final List<Map<String, Object>> semantics;

  /// `routeStackProvider`/`bestEffortRouteStack` output, verbatim.
  final List<String> routes;

  /// `errors.map((e) => e.toJson()).toList()` output, verbatim.
  final List<Map<String, Object?>> errors;

  /// `stability.toJson()` map, verbatim.
  final Map<String, Object?> stability;

  /// Base64 PNG — only present when a screenshot was requested AND captured.
  final String? screenshot;

  @override
  Seed build(PerceptionContext context) => Node(
    'core',
    children: <Seed>[
      Field('semantics', semantics),
      Field('routes', routes),
      Field('errors', errors),
      Field('stability', stability),
      if (screenshot != null) Field('screenshot_png_b64', screenshot),
    ],
  );
}

/// Builds the core perception [Seed] from already-computed core primitives.
///
/// The returned `Node('core', …)`'s child order is exactly the key order
/// [CoreFragmentValues.toMap] emits (semantics, routes, errors, stability,
/// then the optional screenshot), so the serialized fragment is byte-identical
/// to that map. The `screenshot_png_b64` field is OMITTED (not present as a
/// null) when [screenshot] is null, mirroring [CoreFragmentValues.toMap] which
/// only adds the key when a capture succeeds.
Seed buildCorePerceptionSeed({
  required List<Map<String, Object>> semantics,
  required List<String> routes,
  required List<Map<String, Object?>> errors,
  required Map<String, Object?> stability,
  String? screenshot,
}) => CorePerception(
  semantics: semantics,
  routes: routes,
  errors: errors,
  stability: stability,
  screenshot: screenshot,
);
