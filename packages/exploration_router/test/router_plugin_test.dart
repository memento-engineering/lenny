import 'package:exploration_flutter/contract.dart';
import 'package:exploration_router/exploration_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _ctx = ObservationContext(turn: 0, sinceLastAction: Duration.zero);

Widget _app(GlobalKey<NavigatorState> key) => WidgetsApp(
      navigatorKey: key,
      color: const Color(0xFF000000),
      initialRoute: '/',
      onGenerateRoute: (s) => switch (s.name) {
        '/' || '/settings' => PageRouteBuilder<void>(
            settings: s,
            pageBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        _ => null,
      },
    );

class _FakeDelegate extends RouterDelegate<Object> with ChangeNotifier {
  _FakeDelegate(this._cfg);
  Object? _cfg;
  @override
  Object? get currentConfiguration => _cfg;
  @override
  Widget build(BuildContext c) => const SizedBox.shrink();
  @override
  Future<void> setNewRoutePath(Object c) async => _cfg = c;
  @override
  Future<bool> popRoute() async => false;
}

void main() {
  test('namespace is router and tool name is bare "navigate"', () {
    final p = RouterPlugin(navigatorKey: GlobalKey<NavigatorState>());
    expect(p.namespace, 'router');
    expect(p.tools.single.name, 'navigate');
  });

  test('busyState is always idle', () async {
    final p = RouterPlugin(navigatorKey: GlobalKey<NavigatorState>());
    expect((await p.busyState()).isBusy, isFalse);
  });

  testWidgets('observe returns Navigator fragment with route name and stack',
      (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final f = await RouterPlugin(navigatorKey: k).observe(_ctx);
    expect(f!['current_route_name'], '/');
    expect(f['stack'], ['/']);
  });

  testWidgets('observe returns null when NavigatorState not mounted',
      (t) async {
    final p = RouterPlugin(navigatorKey: GlobalKey<NavigatorState>());
    expect(await p.observe(_ctx), isNull);
  });

  testWidgets('navigate pushes named route and observe sees it', (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterPlugin(navigatorKey: k);
    final r = await p.tools.single.call({
      'route_name': '/settings',
      'arguments': {'tab': 'profile'},
    });
    await t.pumpAndSettle();
    expect(r.ok, isTrue);
    expect(r.value, {'route_name': '/settings'});
    final f = await p.observe(_ctx);
    expect(f!['current_route_name'], '/settings');
    expect(f['arguments'], {'tab': 'profile'});
  });

  testWidgets('navigate to unknown route returns ok:false', (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterPlugin(navigatorKey: k);
    final r = await p.tools.single.call({'route_name': '/nope'});
    expect(r.ok, isFalse);
    expect(r.error, contains('/nope'));
  });

  test('declarative-only: observe reads RouterDelegate.currentConfiguration',
      () async {
    final p = RouterPlugin(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('/checkout/payment'),
    );
    final f = await p.observe(_ctx);
    expect(f!['current_route_name'], '/checkout/payment');
    expect(f['stack'], ['/checkout/payment']);
    expect(f['arguments'], isNull);
  });

  testWidgets('mixed: imperative wins when Navigator is mounted', (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterPlugin(
      navigatorKey: k,
      routerDelegate: _FakeDelegate('/declarative'),
    );
    final f = await p.observe(_ctx);
    expect(f!['current_route_name'], '/');
  });

  test('declarative fallback when Navigator unmounted', () async {
    final p = RouterPlugin(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('/fallback'),
    );
    final f = await p.observe(_ctx);
    expect(f!['current_route_name'], '/fallback');
  });

  test('returns null when neither surface yields a route', () async {
    final p = RouterPlugin(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate(null),
    );
    expect(await p.observe(_ctx), isNull);
  });

  test('observation fragment caps at 1024 bytes with _truncated marker',
      () async {
    final p = RouterPlugin(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('x' * 2000),
    );
    final f = await p.observe(_ctx);
    expect(f!['_truncated'], isTrue);
    expect(f['stack'], isEmpty);
  });
}
