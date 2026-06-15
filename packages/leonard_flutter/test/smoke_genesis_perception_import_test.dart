import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Smoke test for the genesis→lenny perception dependency edge.
///
/// Confirms the pinned git dep on `genesis_perception` plus the `genesis_tree`
/// dependency_override resolve, and that the public barrel
/// (`package:genesis_perception/genesis_perception.dart`) compiles from inside
/// the lenny workspace. `Perception` is the framework's config base type; naming
/// it guards against the A9/A12 delta renaming/removing it out from under us.
void main() {
  test('genesis_perception barrel resolves and Perception is accessible', () {
    expect(Perception, isNotNull);
  });
}
