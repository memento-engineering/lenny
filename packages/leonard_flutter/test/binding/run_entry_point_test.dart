import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stub extends LeonardExtension {
  _Stub(this.namespace);
  @override
  final String namespace;
  @override
  List<LeonardTool> get tools => const [];
  @override
  Future<void> initialize(ExtensionContext c) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction a) async {}
  @override
  Future<void> dispose() async {}
}

class _RecApp implements LeonardApp {
  LeonardAppContext? seen;
  @override
  LeonardAppConfig build(LeonardAppContext ctx) {
    seen = ctx;
    return LeonardAppConfig(
      plugins: <LeonardExtension>[_Stub('app_${identityHashCode(this)}')],
      app: const SizedBox.shrink(),
    );
  }
}

void main() {
  test('run installs binding before build callback', () {
    final _RecApp app = _RecApp();
    LeonardBinding.run(app);
    expect(app.seen, isNotNull);
    expect(app.seen!.isProductionMode, isFalse);
    expect(app.seen!.binding, isA<LeonardBinding>());
    expect(WidgetsBinding.instance, isA<LeonardBinding>());
  });

  test('run is idempotent: second call still invokes build', () {
    final _RecApp a2 = _RecApp();
    LeonardBinding.run(a2);
    expect(a2.seen, isNotNull);
    expect(WidgetsBinding.instance, isA<LeonardBinding>());
  });

  test('onTeardown callbacks fire LIFO from drain helper', () async {
    final List<int> order = <int>[];
    final LeonardBinding binding = LeonardBinding.instance;
    binding.debugSetTeardownsForTesting(<Future<void> Function()>[]);
    final _RecApp a3 = _RecApp();
    LeonardBinding.run(a3);
    a3.seen!
      ..onTeardown(() async => order.add(1))
      ..onTeardown(() async => order.add(2))
      ..onTeardown(() async => order.add(3));
    await binding.debugDrainTeardownsForTesting();
    expect(order, <int>[3, 2, 1]);
  });
}
