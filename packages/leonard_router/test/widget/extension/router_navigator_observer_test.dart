library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;
import 'package:leonard_router/leonard_router.dart';

/// Harvest the router extension's observation fragment via the perception path,
/// exactly as the binding's single observation loop does.
Map<String, Object?> _harvest(RouterExtension extension) {
  final genesis.PerceptionOwner owner = genesis.PerceptionOwner();
  try {
    final genesis.Element root = owner.mountRoot(extension.buildPerception());
    return genesis.serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

class _ItemArgs {
  const _ItemArgs();
}

Widget _app(
  GlobalKey<NavigatorState> key, {
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) => MaterialApp(
  navigatorKey: key,
  navigatorObservers: observers,
  initialRoute: '/',
  routes: <String, WidgetBuilder>{
    '/': (_) => const SizedBox.shrink(),
    '/a': (_) => const SizedBox.shrink(),
    '/b': (_) => const SizedBox.shrink(),
  },
);

/// Pushes `/a` (with arguments) and `/b`, then pops `/b`.
Future<void> _pushTwoPopOne(
  WidgetTester t,
  GlobalKey<NavigatorState> key,
) async {
  unawaited(key.currentState!.pushNamed('/a', arguments: const _ItemArgs()));
  unawaited(key.currentState!.pushNamed('/b'));
  await t.pumpAndSettle();
  key.currentState!.pop();
  await t.pumpAndSettle();
}

class _PagesDelegate extends RouterDelegate<Object> with ChangeNotifier {
  _PagesDelegate(this._observer);

  final LeonardNavigatorObserver _observer;

  @override
  Object? get currentConfiguration => '/cart';

  @override
  Widget build(BuildContext context) => Navigator(
    observers: <NavigatorObserver>[_observer],
    pages: const <Page<void>>[
      MaterialPage<void>(name: '/', child: SizedBox.shrink()),
      MaterialPage<void>(name: '/cart', child: SizedBox.shrink()),
    ],
    onDidRemovePage: (_) {},
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Future<bool> popRoute() async => false;
}

void main() {
  testWidgets('observer on a MaterialApp reports its stack after two pushes '
      'and a pop', (WidgetTester t) async {
    final GlobalKey<NavigatorState> k = GlobalKey<NavigatorState>();
    final LeonardNavigatorObserver o = LeonardNavigatorObserver();
    await t.pumpWidget(_app(k, observers: <NavigatorObserver>[o]));
    final RouterExtension p = RouterExtension(
      navigatorKey: k,
      navigatorObservers: <LeonardNavigatorObserver>[o],
    );
    expect(_harvest(p)['stack'], <String>['/']);

    await _pushTwoPopOne(t, k);

    final Map<String, Object?> f = _harvest(p);
    expect(f, <String, Object?>{
      'current_route_name': '/a',
      'stack': <String>['/', '/a'],
      'arguments': null,
      'navigators': <Object?>[
        <String, Object?>{
          'label': null,
          'stack': <Object?>[
            <String, Object?>{'name': '/', 'arguments_type': null},
            <String, Object?>{'name': '/a', 'arguments_type': '_ItemArgs'},
          ],
        },
      ],
    });
    expect(f.keys.toList(), <String>[
      'current_route_name',
      'stack',
      'arguments',
      'navigators',
    ]);
  });

  testWidgets('no observer on a MaterialApp reports the current route only', (
    WidgetTester t,
  ) async {
    final GlobalKey<NavigatorState> k = GlobalKey<NavigatorState>();
    await t.pumpWidget(_app(k));
    final RouterExtension p = RouterExtension(navigatorKey: k);

    await _pushTwoPopOne(t, k);

    expect(_harvest(p), <String, Object?>{
      'current_route_name': '/a',
      'arguments': null,
    });
  });

  testWidgets(
    'observer on the Navigator a RouterDelegate builds supplies the stack',
    (WidgetTester t) async {
      final LeonardNavigatorObserver o = LeonardNavigatorObserver(
        label: 'checkout',
      );
      final _PagesDelegate d = _PagesDelegate(o);
      await t.pumpWidget(MaterialApp(home: Router<Object>(routerDelegate: d)));
      final RouterExtension p = RouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: d,
        navigatorObservers: <LeonardNavigatorObserver>[o],
      );

      expect(_harvest(p), <String, Object?>{
        'current_route_name': '/cart',
        'stack': <String>['/', '/cart'],
        'arguments': null,
        'navigators': <Object?>[
          <String, Object?>{
            'label': 'checkout',
            'stack': <Object?>[
              <String, Object?>{'name': '/', 'arguments_type': null},
              <String, Object?>{'name': '/cart', 'arguments_type': null},
            ],
          },
        ],
      });
    },
  );

  testWidgets('an observer alone makes no snapshot when the top route is '
      'unnamed', (WidgetTester t) async {
    final GlobalKey<NavigatorState> k = GlobalKey<NavigatorState>();
    final LeonardNavigatorObserver o = LeonardNavigatorObserver();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: k,
        navigatorObservers: <NavigatorObserver>[o],
        home: const SizedBox.shrink(),
      ),
    );
    unawaited(
      k.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      ),
    );
    await t.pumpAndSettle();
    final RouterExtension p = RouterExtension(
      navigatorKey: k,
      navigatorObservers: <LeonardNavigatorObserver>[o],
    );

    expect(o.stack, hasLength(2));
    expect(o.stack.last.name, 'MaterialPageRoute<void>');
    expect(p.isPerceptionIdle(), isTrue);
    expect(p.readSnapshot(), isNull);
  });

  testWidgets('an observer alone makes no snapshot when the navigator is not '
      'mounted', (WidgetTester t) async {
    final LeonardNavigatorObserver o = LeonardNavigatorObserver()
      ..didPush(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/a'),
          builder: (_) => const SizedBox.shrink(),
        ),
        null,
      );
    final RouterExtension p = RouterExtension(
      navigatorKey: GlobalKey<NavigatorState>(),
      navigatorObservers: <LeonardNavigatorObserver>[o],
    );

    expect(o.stack, hasLength(1));
    expect(p.isPerceptionIdle(), isTrue);
    expect(p.readSnapshot(), isNull);
  });
}
