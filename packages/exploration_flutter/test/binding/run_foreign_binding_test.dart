import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopApp implements ExplorationApp {
  @override
  ExplorationAppConfig build(ExplorationAppContext ctx) =>
      const ExplorationAppConfig(plugins: <ExplorationPlugin>[], app: SizedBox.shrink());
}

void main() {
  test('run throws StateError when foreign WidgetsBinding is active', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(WidgetsBinding.instance is ExplorationBinding, isFalse,
        reason: 'precondition: foreign binding active');
    expect(
      () => ExplorationBinding.run(_NoopApp()),
      throwsA(isA<StateError>()
          .having((StateError e) => e.message, 'msg',
              contains('ExplorationBinding.run'))
          .having((StateError e) => e.message, 'msg',
              contains('first Flutter-touching line'))),
    );
  });
}
