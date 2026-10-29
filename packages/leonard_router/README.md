# leonard_router

A reference extension for [Leonard](https://github.com/memento-engineering/lenny) — reports the
current route and, when the app installs a `LeonardNavigatorObserver`, the route stack that observer
keeps, as an observation fragment, and adds a `router.navigate` tool.

Add it to a Flutter app that already installs `leonard_flutter`, then register it with the binding.
See the [Leonard README](https://github.com/memento-engineering/lenny#write-an-extension) for usage.

## The route stack

Flutter's navigator does not publish its route history, so the stack is the observer's: a
`LeonardNavigatorObserver` the app installs on its navigator keeps it from the navigator's own push,
pop, replace and remove notifications. The fragment's `stack` lists that observer's route names, top
last, and `navigators` lists each installed observer with each route's name and its arguments' type.

Without the observer only the current route is known: the fragment reports `current_route_name` and
`arguments`, and has no `stack`.

Pass the same observer to the navigator and to the extension.

### On a MaterialApp

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final routerObserver = LeonardNavigatorObserver();

MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [routerObserver],
  routes: routes,
);

RouterExtension(navigatorKey: navigatorKey, navigatorObservers: [routerObserver]);
```

### On a Navigator

```dart
Navigator(
  key: navigatorKey,
  observers: [routerObserver],
  onGenerateRoute: onGenerateRoute,
);

RouterExtension(navigatorKey: navigatorKey, navigatorObservers: [routerObserver]);
```

### On the Navigator a RouterDelegate builds

An app on the Router API installs the observer on the Navigator its delegate builds. The current
route still comes from the delegate's `currentConfiguration`; the stack comes from the observer.

```dart
class AppRouterDelegate extends RouterDelegate<Object> with ChangeNotifier {
  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    observers: [routerObserver],
    pages: pages,
    onDidRemovePage: onDidRemovePage,
  );
  // ...
}

RouterExtension(
  navigatorKey: navigatorKey,
  routerDelegate: delegate,
  navigatorObservers: [routerObserver],
);
```

### Several navigators

Flutter attaches an observer to one navigator only, so an app with several navigators makes one
observer per navigator and gives each a `label`, for example the name of its key:
`LeonardNavigatorObserver(label: 'tabs')`. The extension lists them under `navigators` in the order
the app passes them; the first one's route names fill `stack`.
