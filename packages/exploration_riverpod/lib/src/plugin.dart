import 'dart:convert';

import 'package:exploration_flutter/contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'internals.dart';

class _InvalidateTool extends ExplorationTool {
  _InvalidateTool(this._c, this._o);

  final ProviderContainer _c;
  final ExplorationProviderObserver _o;

  @override
  String get name => 'invalidate_provider';

  @override
  String get description =>
      'Force-refresh a Riverpod provider. provider_id is the provider name '
      'when set, otherwise the provider runtimeType, as surfaced in the '
      'riverpod observation fragment under invalidatable_providers.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['provider_id'],
        'properties': <String, Object?>{
          'provider_id': <String, Object?>{'type': 'string'},
        },
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final id = args['provider_id'];
    if (id is! String) {
      return const ToolResult(
        ok: false,
        error: 'provider_id (string) required',
      );
    }
    final p = _o.live[id];
    if (p == null) {
      return ToolResult(ok: false, error: 'unknown provider_id: $id');
    }
    _c.invalidate(p);
    return const ToolResult(ok: true);
  }
}

/// Reference Riverpod plugin for the Flutter Exploration Agent.
///
/// Hosts MUST construct a `ProviderContainer` with this plugin's
/// [observer] installed (`ProviderContainer(observers: [plugin.observer])`)
/// AND pass that same container to this constructor; otherwise the
/// plugin will report no providers and `invalidate_provider` will be a
/// no-op.
class RiverpodExplorationPlugin extends ExplorationPlugin {
  RiverpodExplorationPlugin({
    required ProviderContainer container,
    ExplorationProviderObserver? observer,
    int observationBudgetBytes = 1024,
  })  : _c = container,
        _o = observer ?? ExplorationProviderObserver(),
        _budget = observationBudgetBytes;

  final ProviderContainer _c;
  final ExplorationProviderObserver _o;
  final int _budget;
  bool _initialized = false;
  late final _InvalidateTool _tool = _InvalidateTool(_c, _o);

  /// The observer this plugin uses to track providers; hosts include it
  /// in their `ProviderContainer(observers: [...])`.
  ExplorationProviderObserver get observer => _o;

  @override
  String get namespace => 'riverpod';

  @override
  List<ExplorationTool> get tools => <ExplorationTool>[_tool];

  @override
  Future<void> initialize(PluginContext c) async {
    _initialized = true;
  }

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    if (!_initialized) return null;
    _o.flushPendingAt(ctx.turn);
    final ids = _o.live.keys.toList(growable: false);
    final ch = _o
        .recentChanges()
        .map((c) => c.toJson())
        .toList(growable: false);
    if (ids.isEmpty && ch.isEmpty) return null;
    return _budgeted(ids, ch);
  }

  Map<String, Object?> _budgeted(
    List<String> ids,
    List<Map<String, Object?>> ch,
  ) {
    Map<String, Object?> shape(List<String> xs, {bool truncated = false}) {
      final m = <String, Object?>{
        'invalidatable_providers': xs,
        'recent_state_changes': ch,
      };
      if (truncated) m['truncated'] = true;
      return m;
    }

    int size(Map<String, Object?> m) => utf8.encode(jsonEncode(m)).length;

    final full = shape(ids);
    if (size(full) <= _budget) return full;

    var lo = 0;
    var hi = ids.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (size(shape(ids.sublist(0, mid), truncated: true)) <= _budget) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return shape(ids.sublist(0, lo), truncated: true);
  }

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction a) async {}

  @override
  Future<void> dispose() async {
    _initialized = false;
    _o.clear();
  }
}
