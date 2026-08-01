import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopApp implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) => const LeonardAppConfig(
    extensions: <LeonardExtension>[],
    app: SizedBox.shrink(),
  );
}

void main() {
  test('run throws StateError when foreign WidgetsBinding is active', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(
      WidgetsBinding.instance is LeonardBinding,
      isFalse,
      reason: 'precondition: foreign binding active',
    );
    expect(
      () => LeonardBinding.run(_NoopApp()),
      throwsA(
        isA<StateError>()
            .having(
              (StateError e) => e.message,
              'msg',
              contains('LeonardBinding.run'),
            )
            .having(
              (StateError e) => e.message,
              'msg',
              contains('first Flutter-touching line'),
            ),
      ),
    );
  });
}
