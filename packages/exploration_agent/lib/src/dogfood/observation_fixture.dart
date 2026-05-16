/// Observation-fixture loader for the dogfood harness
/// (bead lenny-cx6.43).
///
/// Reads a JSON file matching the binding's `core.get_stable_observation`
/// response shape and returns it as the canned observation the harness
/// installs into its binding fake. The shape is preserved verbatim — no
/// coupling to the typed `Observation` here; the fake speaks wire JSON
/// and the agent decodes it.
///
/// Note: this file imports `dart:io`. It lives under `lib/src/dogfood/`,
/// which the `tool/check_no_dart_io.dart` guard whitelists explicitly
/// (the dogfood subtree is private and not exported from
/// `lib/exploration_agent.dart`).
library;

import 'dart:convert';
import 'dart:io';

import 'types.dart';

/// One canned observation payload, ready to be served by the binding
/// fake when the agent calls `core.get_stable_observation`.
class ObservationFixture {
  ObservationFixture._(this.path, this.body);

  /// Source path the fixture was loaded from. The literal string
  /// `'<empty>'` is used when [empty] constructs the fixture.
  final String path;

  /// Decoded top-level JSON object.
  final Map<String, dynamic> body;

  /// Load a fixture from disk. Throws [DogfoodConfigError] when the
  /// file is missing or the top-level JSON value is not an object.
  static Future<ObservationFixture> loadFromFile(String path) async {
    final File f = File(path);
    if (!await f.exists()) {
      throw DogfoodConfigError('observation fixture not found: $path');
    }
    final String text = await f.readAsString();
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw DogfoodConfigError(
        'observation fixture is not valid JSON: $path (${e.message})',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw DogfoodConfigError(
        'observation fixture must be a JSON object at top level: $path',
      );
    }
    return ObservationFixture._(path, decoded);
  }

  /// Minimal empty observation — what the harness returns when no
  /// fixture is supplied. The agent's prompt assembler will note the
  /// scarcity but must not crash.
  static ObservationFixture empty() => ObservationFixture._(
        '<empty>',
        <String, dynamic>{
          'frame_id': 1,
          'semantics': <String, dynamic>{'nodes': <dynamic>[]},
          'plugins': <String, dynamic>{},
        },
      );
}
