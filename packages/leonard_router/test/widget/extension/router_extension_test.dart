import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_router/leonard_router.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Harvest the router extension's observation fragment via the perception path,
/// exactly as the binding's single observation loop does.
Map<String, Object?> _harvest(RouterExtension extension) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(extension.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

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

  void setConfiguration(Object? value) {
    _cfg = value;
    notifyListeners();
  }

  @override
  Object? get currentConfiguration => _cfg;
  @override
  Widget build(BuildContext c) => const SizedBox.shrink();
  @override
  Future<void> setNewRoutePath(Object c) async => _cfg = c;
  @override
  Future<bool> popRoute() async => false;
}

class _FakeCountingRouterExtension extends RouterExtension {
  _FakeCountingRouterExtension({
    required super.navigatorKey,
    super.routerDelegate,
    super.navigate,
  });

  int readSnapshotCalls = 0;

  @override
  RouteSnapshot? readSnapshot() {
    readSnapshotCalls += 1;
    return super.readSnapshot();
  }
}

void main() {
  test('namespace is router and tool name is bare "navigate"', () {
    final p = RouterExtension(navigatorKey: GlobalKey<NavigatorState>());
    expect(p.namespace, 'router');
    expect(p.tools.single.name, 'navigate');
  });

  test('busyState is always idle', () async {
    final p = RouterExtension(navigatorKey: GlobalKey<NavigatorState>());
    expect((await p.busyState()).isBusy, isFalse);
  });

  testWidgets('observation has Navigator fragment with route name and stack', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterExtension(navigatorKey: k);
    expect(p.isPerceptionIdle(), isFalse);
    final f = _harvest(p);
    expect(f['current_route_name'], '/');
    expect(f['stack'], ['/']);
  });

  testWidgets('isPerceptionIdle is true when NavigatorState not mounted', (
    t,
  ) async {
    final p = RouterExtension(navigatorKey: GlobalKey<NavigatorState>());
    expect(p.isPerceptionIdle(), isTrue);
  });

  testWidgets('navigate pushes named route and reports effective route', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterExtension(navigatorKey: k);
    final r = await p.tools.single.call({
      'route_name': '/settings',
      'arguments': {'tab': 'profile'},
    });
    expect(r.ok, isTrue);
    expect(r.value, {
      'route_name': '/settings',
      'effective_route': '/settings',
    });
    await t.pumpAndSettle();
    final f = _harvest(p);
    expect(f['current_route_name'], '/settings');
    expect(f['arguments'], {'tab': 'profile'});
  });

  testWidgets('navigate to unknown route returns ok:false', (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterExtension(navigatorKey: k);
    final r = await p.tools.single.call({'route_name': '/nope'});
    expect(r.ok, isFalse);
    expect(r.error, contains('/nope'));
  });

  testWidgets('navigate uses the navigation seam when provided', (t) async {
    String? gotName;
    Map<String, Object?>? gotArgs;
    final p = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
      navigate: (name, args) async {
        gotName = name;
        gotArgs = args;
      },
    );
    final invocation = p.tools.single.call({
      'route_name': 'settings',
      'arguments': {'tab': 'profile'},
    });
    await t.pump();
    await t.pump();
    final r = await invocation;
    expect(r.ok, isTrue);
    expect(r.value, {'route_name': 'settings', 'effective_route': null});
    expect(gotName, 'settings');
    expect(gotArgs, {'tab': 'profile'});
  });

  testWidgets(
    'navigate reports redirected effective route from shared snapshot',
    (t) async {
      final delegate = _FakeDelegate('/home');
      final p = _FakeCountingRouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: delegate,
        navigate: (name, args) async {
          expect(name, 'settings');
          SchedulerBinding.instance.addPostFrameCallback((_) {
            delegate.setConfiguration('/login');
          });
        },
      );

      final invocation = p.tools.single.call({'route_name': 'settings'});
      await t.pump();
      await t.pump();
      final r = await invocation;

      expect(r.ok, isTrue);
      expect(r.value, {'route_name': 'settings', 'effective_route': '/login'});
      expect(p.readSnapshotCalls, 1);

      final f = _harvest(p);
      final value = r.value! as Map<String, Object?>;
      expect(f['current_route_name'], value['effective_route']);
    },
  );

  test('navigate seam errors surface as ok:false', () async {
    final p = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
      navigate: (name, args) async =>
          throw StateError('no GoRoute named "$name"'),
    );
    final r = await p.tools.single.call({'route_name': 'nope'});
    expect(r.ok, isFalse);
    expect(r.error, contains('nope'));
  });

  testWidgets('seam is preferred over Navigator pushNamed when both present', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    var seamCalled = false;
    final p = RouterExtension(
      navigatorKey: k,
      navigate: (name, args) async => seamCalled = true,
    );
    final invocation = p.tools.single.call({'route_name': '/settings'});
    await t.pump();
    await t.pump();
    final r = await invocation;
    expect(r.ok, isTrue);
    expect(r.value, {'route_name': '/settings', 'effective_route': '/'});
    expect(seamCalled, isTrue);
    // The seam handled navigation; Navigator-1.0 pushNamed must NOT have run,
    // so the Navigator stack is untouched (still at root).
    await t.pumpAndSettle();
    final f = _harvest(p);
    expect(f['current_route_name'], '/');
  });

  test('navigate advertises requested and effective route semantics', () {
    final tool = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
    ).tools.single;
    final schema = tool.inputSchema.raw;
    final properties = schema['properties']! as Map<String, Object?>;
    final routeName = properties['route_name']! as Map<String, Object?>;
    final description = tool.description.toLowerCase();
    final schemaDescription = <String>[
      schema['description']! as String,
      routeName['description']! as String,
    ].join(' ').toLowerCase();
    final semantics = allOf(
      contains('request'),
      contains('nullable'),
      contains('effective_route'),
      contains('redirect'),
      contains('ok'),
      contains('true'),
    );

    expect(description, semantics);
    expect(schemaDescription, semantics);
  });

  test('declarative-only: reads RouterDelegate.currentConfiguration', () async {
    final p = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('/checkout/payment'),
    );
    expect(p.isPerceptionIdle(), isFalse);
    final f = _harvest(p);
    expect(f['current_route_name'], '/checkout/payment');
    expect(f['stack'], ['/checkout/payment']);
    expect(f['arguments'], isNull);
  });

  testWidgets('mixed: imperative wins when Navigator is mounted', (t) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final p = RouterExtension(
      navigatorKey: k,
      routerDelegate: _FakeDelegate('/declarative'),
    );
    final f = _harvest(p);
    expect(f['current_route_name'], '/');
  });

  test('declarative fallback when Navigator unmounted', () async {
    final p = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('/fallback'),
    );
    final f = _harvest(p);
    expect(f['current_route_name'], '/fallback');
  });

  test(
    'isPerceptionIdle is true when neither surface yields a route',
    () async {
      final p = RouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: _FakeDelegate(null),
      );
      expect(p.isPerceptionIdle(), isTrue);
    },
  );
}
