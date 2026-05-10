import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stub extends ExplorationPlugin {
  _Stub(this.namespace);
  @override
  final String namespace;
  @override
  List<ExplorationTool> get tools => const [];
  @override
  Future<void> initialize(PluginContext c) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext c) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction a) async {}
  @override
  Future<void> dispose() async {}
}

class _RecApp implements ExplorationApp {
  ExplorationAppContext? seen;
  @override
  ExplorationAppConfig build(ExplorationAppContext ctx) {
    seen = ctx;
    return ExplorationAppConfig(
      plugins: <ExplorationPlugin>[_Stub('app_${identityHashCode(this)}')],
      app: const SizedBox.shrink(),
    );
  }
}

void main() {
  test('run installs binding before build callback', () {
    final _RecApp app = _RecApp();
    ExplorationBinding.run(app);
    expect(app.seen, isNotNull);
    expect(app.seen!.isProductionMode, isFalse);
    expect(app.seen!.binding, isA<ExplorationBinding>());
    expect(WidgetsBinding.instance, isA<ExplorationBinding>());
  });

  test('run is idempotent: second call still invokes build', () {
    final _RecApp a2 = _RecApp();
    ExplorationBinding.run(a2);
    expect(a2.seen, isNotNull);
    expect(WidgetsBinding.instance, isA<ExplorationBinding>());
  });

  test('onTeardown callbacks fire LIFO from drain helper', () async {
    final List<int> order = <int>[];
    final ExplorationBinding binding = ExplorationBinding.instance;
    binding.debugSetTeardownsForTesting(<Future<void> Function()>[]);
    final _RecApp a3 = _RecApp();
    ExplorationBinding.run(a3);
    a3.seen!
      ..onTeardown(() async => order.add(1))
      ..onTeardown(() async => order.add(2))
      ..onTeardown(() async => order.add(3));
    await binding.debugDrainTeardownsForTesting();
    expect(order, <int>[3, 2, 1]);
  });
}
