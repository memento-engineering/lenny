import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

class _StubExtension extends LeonardExtension {
  const _StubExtension(this.namespace);
  @override
  final String namespace;
  @override
  List<LeonardTool> get tools => const [];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  // Once a Flutter binding is installed in a process it cannot be torn down
  // and re-installed (BindingBase asserts _debugInitializedType is null). All
  // lifecycle assertions therefore run against the single shared install.
  late LeonardBinding initial;

  setUpAll(() {
    initial = LeonardBinding.ensureInitialized(extensions: const [
      _StubExtension('a'),
      _StubExtension('b'),
      _StubExtension('a'),
    ])!;
  });

  test('installs as WidgetsBinding in debug', () {
    expect(initial, isNotNull);
    expect(WidgetsBinding.instance, same(initial));
  });

  test('preserves plugin list verbatim (order + duplicates)', () {
    expect(initial.plugins.map((p) => p.namespace).toList(),
        <String>['a', 'b', 'a']);
  });

  test('plugins getter returns an unmodifiable list', () {
    expect(() => initial.plugins.add(const _StubExtension('c')),
        throwsUnsupportedError);
  });

  test('idempotent: second call returns same instance', () {
    final second =
        LeonardBinding.ensureInitialized(extensions: const [_StubExtension('z')]);
    expect(identical(initial, second), isTrue,
        reason: 'second call must return the existing binding without '
            'replacing the plugin list');
    expect(initial.plugins.map((p) => p.namespace).toList(),
        <String>['a', 'b', 'a'],
        reason: 'idempotent call must not mutate the stored plugin list');
  });
}
