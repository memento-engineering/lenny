import 'dart:developer' as developer;
import 'package:flutter_test/flutter_test.dart';
import 'package:exploration_flutter/exploration_flutter.dart';

void main() {
  tearDown(ExplorationBinding.debugReset);

  test('handshake extension is registered exactly once', () {
    ExplorationBinding.ensureInitialized(plugins: const []);
    expect(kExplorationExtensionPrefix, 'ext.flutter.exploration');
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
          'ext.flutter.exploration.core.handshake',
          (m, p) async => developer.ServiceExtensionResponse.result('{}')),
      throwsArgumentError,
    );
  });
}
