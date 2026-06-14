library;

import 'dart:convert';
import 'dart:io';

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/test_support/observation_equivalence.dart';
import 'package:exploration_flutter/test_support/perception_serializer.dart';
import 'package:exploration_router/exploration_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

const ObservationContext _kCtx = ObservationContext(
  turn: 0,
  sinceLastAction: Duration.zero,
);

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
    '../exploration_flutter/',
    'packages/exploration_flutter/',
    '../../packages/exploration_flutter/',
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

Map<String, Object?> _harvestPlugin(RouterPlugin plugin) =>
    _harvest(plugin.buildPerception());

Map<String, Object?> _wrapObs(Map<String, Object?> routerFrag) =>
    <String, Object?>{
      'semantics': <Object?>[],
      'routes': <Object?>[],
      'errors': <Object?>[],
      'stability': <String, Object?>{},
      'plugins': <String, Object?>{'router': routerFrag},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Navigator happy path: perception fragment equals legacy', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final plugin = RouterPlugin(navigatorKey: k);

    final Map<String, Object?>? legacy = await plugin.observe(_kCtx);
    expect(
      legacy,
      isNotNull,
      reason: 'legacy observe() must emit with a mounted Navigator',
    );

    final Map<String, Object?> perceptionFrag = _harvestPlugin(plugin);

    assertObservationEquivalent(_wrapObs(legacy!), _wrapObs(perceptionFrag));
  });

  testWidgets('arguments-present path: perception arguments equal legacy', (
    t,
  ) async {
    final k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final plugin = RouterPlugin(navigatorKey: k);
    final r = await plugin.tools.single.call({
      'route_name': '/settings',
      'arguments': {'tab': 'profile'},
    });
    expect(r.ok, isTrue);
    await t.pumpAndSettle();

    final Map<String, Object?>? legacy = await plugin.observe(_kCtx);
    expect(legacy, isNotNull);
    expect(legacy!['arguments'], {'tab': 'profile'});

    final Map<String, Object?> perceptionFrag = _harvestPlugin(plugin);

    expect(perceptionFrag['arguments'], legacy['arguments']);
    assertObservationEquivalent(_wrapObs(legacy), _wrapObs(perceptionFrag));
  });

  test('RouterDelegate (declarative) path: perception equals legacy', () async {
    final plugin = RouterPlugin(
      navigatorKey: GlobalKey<NavigatorState>(),
      routerDelegate: _FakeDelegate('/checkout/payment'),
    );

    final Map<String, Object?>? legacy = await plugin.observe(_kCtx);
    expect(legacy, isNotNull);
    expect(legacy!['current_route_name'], '/checkout/payment');
    expect(legacy['stack'], ['/checkout/payment']);
    expect(legacy['arguments'], isNull);

    final Map<String, Object?> perceptionFrag = _harvestPlugin(plugin);

    assertObservationEquivalent(_wrapObs(legacy), _wrapObs(perceptionFrag));
  });

  test(
    'idle null-gate: legacy observe() is null when no surface yields a route',
    () async {
      final plugin = RouterPlugin(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: _FakeDelegate(null),
      );

      final Map<String, Object?>? legacy = await plugin.observe(_kCtx);
      expect(
        legacy,
        isNull,
        reason:
            'binding null-gate (exploration_binding.dart:696) suppresses '
            'the perception fragment when observe() is null',
      );

      // The shared snapshot reader is null too, so the anchor agrees with
      // observe(): the perception path is never reached for an idle plugin.
      expect(plugin.readSnapshot(), isNull);
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
        (goldenObs['plugins'] as Map).cast<String, Object?>()['router']
            as Map<String, Object?>;

    // Byte-equivalence: key order AND null arguments must match the golden.
    expect(jsonEncode(perceptionFrag), jsonEncode(goldenRouter));
  });
}
