library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/test_support/perception_serializer.dart';
import 'package:leonard_router/leonard_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

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
  final Object? _cfg;
  @override
  Object? get currentConfiguration => _cfg;
  @override
  Widget build(BuildContext c) => const SizedBox.shrink();
  @override
  Future<void> setNewRoutePath(Object c) async {}
  @override
  Future<bool> popRoute() async => false;
}

/// Stand-in anchor that returns a fixed [RouteSnapshot] — used to harvest the
/// perception fragment for the exact golden scenario without depending on
/// Navigator stack-walk ordering.
class _FixedAnchor implements PerceptionAnchor<RouteSnapshot?> {
  const _FixedAnchor(this._snap);
  final RouteSnapshot? _snap;
  @override
  RouteSnapshot? read() => _snap;
}

/// Resolves the committed golden whether the test runs with cwd at the router
/// package dir (melos default) or at the workspace root.
File _goldenFile() {
  const String rel = 'test/goldens/router.observation.json';
  for (final String prefix in <String>[
    '../leonard_flutter/',
    'packages/leonard_flutter/',
    '../../packages/leonard_flutter/',
  ]) {
    final File f = File('$prefix$rel');
    if (f.existsSync()) return f;
  }
  throw FileSystemException(
    'Cannot locate router golden — run from router package or workspace root',
    rel,
  );
}

Map<String, Object?> _harvest(Seed seed) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(seed);
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

Map<String, Object?> _harvestExtension(RouterExtension extension) =>
    _harvest(extension.buildPerception());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Navigator happy path: perception fragment surfaces the route', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final extension = RouterExtension(navigatorKey: k);

    expect(
      extension.isPerceptionIdle(),
      isFalse,
      reason: 'a mounted Navigator yields a route snapshot',
    );

    final Map<String, Object?> perceptionFrag = _harvestExtension(extension);
    expect(perceptionFrag['current_route_name'], '/');
    expect(perceptionFrag['stack'], <String>['/']);
  });

  testWidgets('arguments-present path: perception carries the arguments', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final extension = RouterExtension(navigatorKey: k);
    final r = await extension.tools.single.call({
      'route_name': '/settings',
      'arguments': {'tab': 'profile'},
    });
    expect(r.ok, isTrue);
    await t.pumpAndSettle();

    final Map<String, Object?> perceptionFrag = _harvestExtension(extension);
    expect(perceptionFrag['arguments'], {'tab': 'profile'});
  });

  test(
    'RouterDelegate (declarative) path: perception reads the config',
    () async {
      final extension = RouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: _FakeDelegate('/checkout/payment'),
      );

      expect(extension.isPerceptionIdle(), isFalse);
      final Map<String, Object?> perceptionFrag = _harvestExtension(extension);
      expect(perceptionFrag['current_route_name'], '/checkout/payment');
      expect(perceptionFrag['stack'], ['/checkout/payment']);
      expect(perceptionFrag['arguments'], isNull);
    },
  );

  test(
    'idle gate: isPerceptionIdle() is true when no surface yields a route',
    () async {
      final extension = RouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: _FakeDelegate(null),
      );

      // isPerceptionIdle() reproduces the retired observe()==null suppression;
      // the binding skips the router ns entirely. The shared snapshot reader is
      // null too, so the idle gate and the anchor can never drift.
      expect(extension.isPerceptionIdle(), isTrue);
      expect(extension.readSnapshot(), isNull);
    },
  );

  test('golden byte-equivalence: perception fragment matches committed golden', () {
    // Canonical golden case: current_route_name "home", stack ["login","home"],
    // arguments null. Drive the perception build through the same code path the
    // binding uses (RouterPerception over a RouteSnapshotAnchor), via a fixed
    // anchor that supplies the golden snapshot.
    const RouteSnapshot golden = RouteSnapshot(
      currentRouteName: 'home',
      stack: <String>['login', 'home'],
      arguments: null,
    );
    final Map<String, Object?> perceptionFrag = _harvest(
      RouterPerception(const _FixedAnchor(golden)),
    );

    final file = _goldenFile();
    final Map<String, Object?> goldenObs =
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
    final Map<String, Object?> goldenRouter =
        (goldenObs['extensions'] as Map).cast<String, Object?>()['router']
            as Map<String, Object?>;

    // Byte-equivalence: key order AND null arguments must match the golden.
    expect(jsonEncode(perceptionFrag), jsonEncode(goldenRouter));
  });
}
