import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('BindingNotInitializedError', () {
    test('is a StateError', () {
      expect(BindingNotInitializedError(), isA<StateError>());
    });

    test('message contains the host setup snippet', () {
      final err = BindingNotInitializedError();
      expect(err.message, contains('LeonardBinding.ensureInitialized'));
      expect(err.message, contains('kDebugMode'));
      expect(err.message, contains('runApp'));
    });
  });
}
