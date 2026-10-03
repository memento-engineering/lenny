import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;

/// Smoke test for the genesis→lenny perception dependency edge.
///
/// Confirms the hosted `genesis_perception` dependency and public barrel
/// (`package:genesis_perception/genesis_perception.dart`) compiles from inside
/// the lenny workspace without retargeting Flutter's identically named types.
void main() {
  test('Flutter and Genesis tree vocabularies remain distinct', () {
    expect(genesis.Perception, isNotNull);
    expect(Element, isNot(same(genesis.Element)));
    expect(BuildContext, isNot(same(genesis.BuildContext)));
  });
}
