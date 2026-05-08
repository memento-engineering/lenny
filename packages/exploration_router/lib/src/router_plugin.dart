import 'dart:async';
import 'dart:convert';

import 'package:exploration_flutter/contract.dart';
import 'package:flutter/widgets.dart';

class RouterPlugin extends ExplorationPlugin {
  RouterPlugin({required this.navigatorKey, this.routerDelegate});

  final GlobalKey<NavigatorState> navigatorKey;
  final RouterDelegate<Object>? routerDelegate;

  static const int _budgetBytes = 1024;

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

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    final imp = _readNavigator();
    if (imp != null) return _capped(imp);
    final dec = _readRouterDelegate();
    if (dec != null) return _capped(dec);
    return null;
  }

  Map<String, Object?>? _readNavigator() {
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
    return {
      'current_route_name': top,
      'stack': stack,
      'arguments': topArgs,
    };
  }

  Map<String, Object?>? _readRouterDelegate() {
    final d = routerDelegate;
    if (d == null) return null;
    final c = d.currentConfiguration;
    if (c == null) return null;
    final n = c.toString();
    return {
      'current_route_name': n,
      'stack': <String>[n],
      'arguments': null,
    };
  }

  static Map<String, Object?> _capped(Map<String, Object?> raw) {
    if (jsonEncode(raw).length <= _budgetBytes) return raw;
    return {
      'current_route_name': raw['current_route_name'],
      'stack': const <String>[],
      'arguments': null,
      '_truncated': true,
    };
  }
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
    final state = _plugin.navigatorKey.currentState;
    if (state == null) {
      return const ToolResult(
        ok: false,
        error: 'NavigatorState is not currently mounted',
      );
    }
    final raw = args['arguments'];
    final routeArgs = raw is Map<String, Object?> ? raw : null;
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
