import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';

void main() {
  test('extension method is auto-namespaced', () {
    expect(
      ExtensionContext.buildExtensionMethodName('router', 'ping'),
      'ext.exploration.router.ping',
    );
  });
}
