import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exploration_flutter/exploration_flutter.dart';

void main() {
  test('throws StateError when another binding is active', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(WidgetsBinding.instance is ExplorationBinding, isFalse,
        reason: 'precondition: foreign binding active');
    expect(
      () => ExplorationBinding.ensureInitialized(plugins: const []),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('another WidgetsBinding'))),
    );
  });
}
