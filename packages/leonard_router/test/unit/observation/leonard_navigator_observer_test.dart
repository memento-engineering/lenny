library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;
import 'package:leonard_router/leonard_router.dart';

class _TestRoute extends Route<void> {
  _TestRoute([String? name, Object? arguments])
    : super(
        settings: RouteSettings(name: name, arguments: arguments),
      );
}

class _ItemArgs {
  const _ItemArgs();
}

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

List<Map<String, Object?>> _stackOf(LeonardNavigatorObserver observer) =>
    observer.stack.map((ObservedRoute e) => e.toJson()).toList();

Map<String, Object?> _harvest(RouterExtension extension) {
  final genesis.PerceptionOwner owner = genesis.PerceptionOwner();
  try {
    final genesis.Element root = owner.mountRoot(extension.buildPerception());
    return genesis.serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps the stack through push, pop, replace and remove', () {
    final LeonardNavigatorObserver observer = LeonardNavigatorObserver();
    final _TestRoute root = _TestRoute('/');
    final _TestRoute a = _TestRoute('/a', const _ItemArgs());
    final _TestRoute unnamed = _TestRoute();
    final _TestRoute c = _TestRoute('/c');
    final _TestRoute x = _TestRoute('/x');
    final _TestRoute d = _TestRoute('/d');

    observer.didPush(root, null);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
    ]);

    observer.didPush(a, root);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
      <String, Object?>{'name': '/a', 'arguments_type': '_ItemArgs'},
    ]);

    observer.didPush(unnamed, a);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
      <String, Object?>{'name': '/a', 'arguments_type': '_ItemArgs'},
      <String, Object?>{'name': '_TestRoute', 'arguments_type': null},
    ]);

    observer.didReplace(newRoute: c, oldRoute: unnamed);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
      <String, Object?>{'name': '/a', 'arguments_type': '_ItemArgs'},
      <String, Object?>{'name': '/c', 'arguments_type': null},
    ]);

    observer.didRemove(a, root);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
      <String, Object?>{'name': '/c', 'arguments_type': null},
    ]);

    observer.didPop(c, root);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
    ]);

    // Popping a route the observer no longer tracks leaves the stack as is.
    observer.didPop(a, root);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
    ]);

    // Replacing an untracked route appends the new one.
    observer.didReplace(newRoute: d, oldRoute: x);
    expect(_stackOf(observer), <Map<String, Object?>>[
      <String, Object?>{'name': '/', 'arguments_type': null},
      <String, Object?>{'name': '/d', 'arguments_type': null},
    ]);
  });

  test('the returned stack is unmodifiable', () {
    final LeonardNavigatorObserver observer = LeonardNavigatorObserver()
      ..didPush(_TestRoute('/'), null);
    final List<ObservedRoute> stack = observer.stack;
    expect(() => stack.add(stack.first), throwsUnsupportedError);
  });

  test('label is null when the app gives none', () {
    expect(LeonardNavigatorObserver().label, isNull);
  });

  test('toJson carries the label and the stack', () {
    final LeonardNavigatorObserver observer = LeonardNavigatorObserver(
      label: 'tabs',
    )..didPush(_TestRoute('/'), null);
    expect(observer.toJson(), <String, Object?>{
      'label': 'tabs',
      'stack': <Object?>[
        <String, Object?>{'name': '/', 'arguments_type': null},
      ],
    });
  });

  test(
    'several observers report as navigators in order under their labels',
    () {
      final LeonardNavigatorObserver root =
          LeonardNavigatorObserver(label: 'root')
            ..didPush(_TestRoute('/'), null)
            ..didPush(_TestRoute('/home'), null);
      final LeonardNavigatorObserver tabs = LeonardNavigatorObserver(
        label: 'tabs',
      )..didPush(_TestRoute('/feed'), null);
      final RouterExtension p = RouterExtension(
        navigatorKey: GlobalKey<NavigatorState>(),
        routerDelegate: _FakeDelegate('/home'),
        navigatorObservers: <LeonardNavigatorObserver>[root, tabs],
      );

      final Map<String, Object?> f = _harvest(p);
      expect(f, <String, Object?>{
        'current_route_name': '/home',
        'stack': <String>['/', '/home'],
        'arguments': null,
        'navigators': <Object?>[root.toJson(), tabs.toJson()],
      });
      expect(
        <Object?>[
          for (final Object? n in f['navigators']! as List<Object?>)
            (n! as Map<String, Object?>)['label'],
        ],
        <String>['root', 'tabs'],
      );
    },
  );
}
