// ExtensionContext owns one side effect — registering a VM service
// extension under the namespaced method name. A test that only asserts the
// composed name leaves the registration itself free to be deleted, so this
// suite asserts the side effect too.

import 'dart:developer' as developer;

import 'package:leonard_contract/leonard_contract.dart';
import 'package:test/test.dart';

Future<developer.ServiceExtensionResponse> _handler(
  String method,
  Map<String, String> parameters,
) async => developer.ServiceExtensionResponse.result('{}');

void main() {
  test('buildExtensionMethodName composes ext.leonard.<ns>.<suffix>', () {
    expect(
      ExtensionContext.buildExtensionMethodName('core', 'tap'),
      'ext.leonard.core.tap',
    );
    // The prefix constant, not a hard-coded copy of it.
    expect(
      ExtensionContext.buildExtensionMethodName('core', 'tap'),
      startsWith('$kLeonardExtensionPrefix.'),
    );
  });

  test('registerExtension registers under the namespaced method name', () {
    ExtensionContext(namespace: 'ctxa').registerExtension('ping', _handler);

    // dart:developer rejects a second registration of the same method name.
    // That throw is reachable only if the first call actually registered,
    // which is what makes the side effect observable in-process.
    expect(
      () => developer.registerExtension('ext.leonard.ctxa.ping', _handler),
      throwsArgumentError,
      reason: 'the name must already be taken by registerExtension',
    );
  });

  test('registerExtension namespaces per context, not globally', () {
    ExtensionContext(namespace: 'ctxb').registerExtension('ping', _handler);
    ExtensionContext(namespace: 'ctxc').registerExtension('ping', _handler);

    // Same suffix, different namespaces — both must have landed on distinct
    // method names, so neither registration collided.
    expect(
      () => developer.registerExtension('ext.leonard.ctxb.ping', _handler),
      throwsArgumentError,
    );
    expect(
      () => developer.registerExtension('ext.leonard.ctxc.ping', _handler),
      throwsArgumentError,
    );
  });

  test('the context carries the namespace it was built with', () {
    expect(ExtensionContext(namespace: 'core').namespace, 'core');
  });
}
