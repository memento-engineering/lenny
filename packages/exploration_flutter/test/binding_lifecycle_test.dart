import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';

class _StubPlugin extends ExplorationPlugin {
  const _StubPlugin(this.namespace);
  @override
  final String namespace;
  @override
  List<ExplorationTool> get tools => const [];
  @override
  Future<void> initialize(PluginContext ctx) async {}
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
  late ExplorationBinding initial;

  setUpAll(() {
    initial = ExplorationBinding.ensureInitialized(plugins: const [
      _StubPlugin('a'),
      _StubPlugin('b'),
      _StubPlugin('a'),
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
    expect(() => initial.plugins.add(const _StubPlugin('c')),
        throwsUnsupportedError);
  });

  test('idempotent: second call returns same instance', () {
    final second =
        ExplorationBinding.ensureInitialized(plugins: const [_StubPlugin('z')]);
    expect(identical(initial, second), isTrue,
        reason: 'second call must return the existing binding without '
            'replacing the plugin list');
    expect(initial.plugins.map((p) => p.namespace).toList(),
        <String>['a', 'b', 'a'],
        reason: 'idempotent call must not mutate the stored plugin list');
  });
}
