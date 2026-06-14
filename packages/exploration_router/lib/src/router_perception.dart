library;

import 'package:exploration_flutter/contract.dart';
import 'package:genesis_perception/genesis_perception.dart';

import 'router_plugin.dart';

/// Perception-native build for the router fragment.
///
/// Mirrors dio's `DioPerception`: a [StatelessPerception] whose [build] emits a
/// `Node('router', …)`. Unlike dio (which reads a plain interceptor model), the
/// router's state lives in Flutter's Navigator/RouterDelegate, so this reads a
/// synchronous [RouteSnapshot] through a [PerceptionAnchor] at observation time.
class RouterPerception extends StatelessPerception {
  /// Creates a router perception backed by [_anchor].
  const RouterPerception(this._anchor);

  final PerceptionAnchor<RouteSnapshot?> _anchor;

  @override
  Seed build(PerceptionContext ctx) {
    final RouteSnapshot? snap = _anchor.read();
    // The binding's null-gate (observe()==null) suppresses this fragment when
    // there is no route, so build() is only reached with a non-null snapshot;
    // fall back to an empty triple defensively.
    return Node(
      'router',
      children: <Seed>[
        Field('current_route_name', snap?.currentRouteName),
        Field('stack', snap?.stack ?? const <String>[]),
        Field('arguments', snap?.arguments),
      ],
    );
  }
}

/// Concrete [PerceptionAnchor] that reads the router's shared route snapshot.
///
/// Wraps the [RouterPlugin] and delegates to its single source of truth for the
/// Navigator/RouterDelegate walk, so the perception path and legacy `observe()`
/// can never drift.
class RouteSnapshotAnchor implements PerceptionAnchor<RouteSnapshot?> {
  /// Creates an anchor over [_plugin].
  const RouteSnapshotAnchor(this._plugin);

  final RouterPlugin _plugin;

  @override
  RouteSnapshot? read() => _plugin.readSnapshot();
}
