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

  group('ObservationEnvelopeError', () {
    test('is not a StateError — it must not be caught as transport loss', () {
      final ObservationEnvelopeError error = ObservationEnvelopeError(
        isolateId: 'panel-isolate',
        topLevelKeys: const <String>['type', 'result'],
      );
      expect(error, isA<Error>());
      expect(error, isNot(isA<StateError>()));
    });

    test('sorts the keys and renders them for the footer', () {
      final ObservationEnvelopeError error = ObservationEnvelopeError(
        isolateId: 'panel-isolate',
        topLevelKeys: const <String>['type', 'result'],
      );
      expect(error.isolateId, 'panel-isolate');
      expect(error.topLevelKeys, <String>['result', 'type']);
      expect(error.keySummary, '[result, type]');
      expect(error.toString(), contains('panel-isolate'));
    });
  });
}
