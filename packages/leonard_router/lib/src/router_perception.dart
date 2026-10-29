library;

import 'package:leonard_flutter/contract.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;

import 'leonard_navigator_observer.dart';
import 'router_extension.dart';

/// Perception-native build for the router fragment.
///
/// Mirrors dio's `DioPerception`: a [StatelessPerception] whose [build] emits a
/// `Node('router', …)`. Unlike dio (which reads a plain interceptor model), the
/// router's state lives in Flutter's Navigator/RouterDelegate, so this reads a
/// synchronous [RouteSnapshot] through a [PerceptionAnchor] at observation time.
///
/// The route stack is the installed [LeonardNavigatorObserver]'s, top last:
/// `stack` holds the first observer's route names, and `navigators` lists every
/// installed observer under its label with each route's name and arguments'
/// type. Without an observer only the current route is known, and the fragment
/// carries no `stack` member; a missing snapshot carries none either.
class RouterPerception extends genesis.StatelessPerception {
  /// Creates a router perception backed by [_anchor], listing
  /// [navigatorObservers] under `navigators`.
  const RouterPerception(
    this._anchor, {
    this.navigatorObservers = const <LeonardNavigatorObserver>[],
  });

  final PerceptionAnchor<RouteSnapshot?> _anchor;

  /// The observers the app installed on its navigators, in its order.
  final List<LeonardNavigatorObserver> navigatorObservers;

  @override
  genesis.Component build(genesis.PerceptionContext ctx) {
    final RouteSnapshot? snap = _anchor.read();
    // The stack is reported only when an observer kept one; an absent stack
    // says it is unknown, where an empty one would claim a fact.
    return genesis.Node(
      'router',
      children: <genesis.Component>[
        genesis.Field('current_route_name', snap?.currentRouteName),
        if (snap != null && snap.stack.isNotEmpty)
          genesis.Field('stack', snap.stack),
        genesis.Field('arguments', snap?.arguments),
        if (snap != null && navigatorObservers.isNotEmpty)
          genesis.Field('navigators', <Object?>[
            for (final LeonardNavigatorObserver o in navigatorObservers)
              o.toJson(),
          ]),
      ],
    );
  }
}

/// Concrete [PerceptionAnchor] that reads the router's shared route snapshot.
///
/// Wraps the [RouterExtension] and delegates to its single source of truth for the
/// Navigator/RouterDelegate read, so the perception path and legacy `observe()`
/// can never drift.
class RouteSnapshotAnchor implements PerceptionAnchor<RouteSnapshot?> {
  /// Creates an anchor over [_extension].
  const RouteSnapshotAnchor(this._extension);

  final RouterExtension _extension;

  @override
  RouteSnapshot? read() => _extension.readSnapshot();
}
