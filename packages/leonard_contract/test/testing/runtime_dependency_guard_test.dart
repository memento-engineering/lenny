import 'package:leonard_contract/testing.dart';
import 'package:test/test.dart';

void main() {
  test('runtime dependency names come from dependencies only', () {
    final Map<Object?, Object?> pubspec = <Object?, Object?>{
      'name': 'example',
      'dependencies': <Object?, Object?>{
        'genesis_perception': '^0.3.0',
        'flutter': <Object?, Object?>{'sdk': 'flutter'},
      },
      'dev_dependencies': <Object?, Object?>{'leonard_agent': '^0.2.0'},
    };

    expect(runtimeDependencyNames(pubspec), <String>{
      'genesis_perception',
      'flutter',
    });
  });

  test('a pubspec without dependencies has an empty runtime set', () {
    expect(
      runtimeDependencyNames(<Object?, Object?>{'name': 'example'}),
      isEmpty,
    );
  });

  test('dependency drift names additions and removals, sorted', () {
    expect(
      dependencyDriftMessage(
        package: 'leonard_host',
        actual: <String>{'genesis_perception', 'leonard_agent', 'dio'},
        expected: <String>{'genesis_perception', 'leonard_contract'},
      ),
      'dio was re-added to leonard_host runtime dependencies.\n'
      'leonard_agent was re-added to leonard_host runtime dependencies.\n'
      'leonard_contract was removed from leonard_host runtime dependencies.',
    );
  });

  test('no drift yields an empty message', () {
    expect(
      dependencyDriftMessage(
        package: 'leonard_host',
        actual: <String>{'genesis_perception'},
        expected: <String>{'genesis_perception'},
      ),
      isEmpty,
    );
  });
}
