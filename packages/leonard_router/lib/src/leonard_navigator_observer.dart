import 'package:flutter/widgets.dart';

/// One route on a navigator's stack, as a [LeonardNavigatorObserver] saw it.
@immutable
class ObservedRoute {
  /// Creates an observed route entry.
  const ObservedRoute._({required this.name, required this.argumentsType});

  /// Reads [route]'s current settings: its name, or its runtime type when it
  /// has none, and the runtime type of its arguments.
  factory ObservedRoute.of(Route<dynamic> route) => ObservedRoute._(
    name: route.settings.name ?? route.runtimeType.toString(),
    argumentsType: route.settings.arguments?.runtimeType.toString(),
  );

  /// The route's settings name, or its runtime type when it is unnamed.
  final String name;

  /// The runtime type of the route's arguments, or null when it has none.
  final String? argumentsType;

  /// The entry as the router fragment serializes it.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'arguments_type': argumentsType,
  };
}

/// Keeps a navigator's real route stack from its own notifications.
///
/// Flutter's navigator exposes no public route history, so the stack is kept
/// out of band: the navigator calls [didPush], [didPop], [didReplace] and
/// [didRemove] as its history changes, and [stack] reads the tracked routes
/// synchronously. The observer never calls the navigator.
///
/// The app installs one observer per navigator (Flutter attaches an observer
/// to at most one navigator) through `MaterialApp.navigatorObservers`,
/// `Navigator.observers`, or the `observers` of the Navigator its
/// RouterDelegate builds, and passes the same instances to
/// `RouterExtension(navigatorObservers: ...)`.
class LeonardNavigatorObserver extends NavigatorObserver {
  /// Creates an observer for one navigator, named by [label].
  LeonardNavigatorObserver({this.label});

  /// The name the app gives this navigator (for example the name of the key
  /// it gave it), or null when it gives none.
  final String? label;

  /// The tracked routes, bottom to top.
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  /// The navigator's route stack, top last.
  ///
  /// Derived on read from each route's current settings, so a page-based route
  /// whose page changes reports its current name. The list is unmodifiable.
  List<ObservedRoute> get stack =>
      List<ObservedRoute>.unmodifiable(_routes.map(ObservedRoute.of));

  /// This navigator as the router fragment's `navigators` lists it.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'stack': <Object?>[for (final ObservedRoute e in stack) e.toJson()],
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) {
      // The old route was never seen; the new one is on the navigator all the
      // same, so it is reported rather than lost.
      if (newRoute != null) _routes.add(newRoute);
      return;
    }
    if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
  }
}
