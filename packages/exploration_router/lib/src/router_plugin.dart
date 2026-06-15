import 'dart:async';

import 'package:exploration_flutter/contract.dart';
import 'package:flutter/widgets.dart';
import 'package:genesis_perception/genesis_perception.dart';

import 'router_perception.dart';

class RouterPlugin extends ExplorationPlugin with PerceptionPlugin {
  RouterPlugin({
    required this.navigatorKey,
    this.routerDelegate,
    this.navigate,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final RouterDelegate<Object>? routerDelegate;

  /// App-provided navigation seam for Router-API apps. When set, [_NavigateTool]
  /// drives navigation through this callback (e.g. go_router's `goNamed`)
  /// instead of Navigator-1.0 `pushNamed`, which requires an
  /// `onGenerateRoute` handler that is null under `MaterialApp.router`
  /// (lenny-18q). Left null, the plugin falls back to `pushNamed` so
  /// Navigator-1.0 apps keep working unchanged.
  final Future<void> Function(
    String routeName,
    Map<String, Object?>? arguments,
  )?
  navigate;

  @override
  String get namespace => 'router';

  @override
  late final List<ExplorationTool> tools = [_NavigateTool(this)];

  @override
  Future<void> initialize(PluginContext ctx) async {}

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}

  /// Reproduces the retired `observe() == null` suppression: when the route
  /// walk yields no snapshot, the binding emits no `plugins.router`
  /// fragment.
  @override
  bool isPerceptionIdle() => readSnapshot() == null;

  /// Single source of truth for the route walk shared by [isPerceptionIdle]
  /// and the perception path's [RouteSnapshotAnchor]. Returns null when
  /// neither the Navigator nor the RouterDelegate yields a route — so the
  /// idle gate and the anchor can never drift. Public to the package so the
  /// anchor can read it.
  RouteSnapshot? readSnapshot() => _snapshot();

  RouteSnapshot? _snapshot() {
    final imp = _readNavigator();
    if (imp != null) return imp;
    return _readRouterDelegate();
  }

  RouteSnapshot? _readNavigator() {
    final state = navigatorKey.currentState;
    if (state == null) return null;
    final stack = <String>[];
    String? top;
    Map<String, Object?>? topArgs;
    state.popUntil((route) {
      final n = route.settings.name;
      if (n != null) {
        stack.add(n);
        top = n;
        final a = route.settings.arguments;
        topArgs = a is Map<String, Object?> ? a : null;
      }
      return true; // walk only; never pop
    });
    if (top == null) return null;
    return RouteSnapshot(
      currentRouteName: top,
      stack: stack,
      arguments: topArgs,
    );
  }

  RouteSnapshot? _readRouterDelegate() {
    final d = routerDelegate;
    if (d == null) return null;
    final c = d.currentConfiguration;
    if (c == null) return null;
    final n = c.toString();
    return RouteSnapshot(
      currentRouteName: n,
      stack: <String>[n],
      arguments: null,
    );
  }

  @override
  Seed buildPerception() => RouterPerception(RouteSnapshotAnchor(this));
}

class _NavigateTool extends ExplorationTool {
  _NavigateTool(this._plugin);

  final RouterPlugin _plugin;

  @override
  String get name => 'navigate';

  @override
  String get description =>
      'Programmatically navigate to a registered named route.';

  @override
  JsonSchema get inputSchema => const JsonSchema({
    'type': 'object',
    'properties': {
      'route_name': {'type': 'string'},
      'arguments': {'type': 'object'},
    },
    'required': ['route_name'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final rn = args['route_name'];
    if (rn is! String || rn.isEmpty) {
      return const ToolResult(
        ok: false,
        error: 'route_name is required and must be a String',
      );
    }
    final raw = args['arguments'];
    final routeArgs = raw is Map<String, Object?> ? raw : null;

    // Prefer the app-provided navigation seam (Router-API apps such as
    // go_router, where Navigator.onGenerateRoute is null and pushNamed cannot
    // resolve a named route — lenny-18q).
    final navigate = _plugin.navigate;
    if (navigate != null) {
      try {
        await navigate(rn, routeArgs);
        return ToolResult(ok: true, value: {'route_name': rn});
      } catch (e) {
        return ToolResult(ok: false, error: 'unknown route "$rn": $e');
      }
    }

    // Fallback: Navigator-1.0 named routes (apps that supply onGenerateRoute).
    final state = _plugin.navigatorKey.currentState;
    if (state == null) {
      return const ToolResult(
        ok: false,
        error: 'NavigatorState is not currently mounted',
      );
    }
    try {
      // Don't await: pushNamed's Future only resolves when the route is
      // popped, but the tool's contract is to return as soon as navigation
      // is kicked off. Synchronous failures (e.g. unknown route) still
      // surface here because Navigator asserts before returning the Future.
      unawaited(state.pushNamed<Object?>(rn, arguments: routeArgs));
      return ToolResult(ok: true, value: {'route_name': rn});
    } on FlutterError catch (e) {
      return ToolResult(ok: false, error: 'unknown route "$rn": ${e.message}');
    }
  }
}
