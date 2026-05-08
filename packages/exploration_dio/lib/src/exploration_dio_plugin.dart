import 'dart:async';

import 'package:dio/dio.dart';
import 'package:exploration_flutter/contract.dart';

import 'dio_tracking_interceptor.dart';
import 'observation_budget.dart';

/// Reference plugin for `package:dio` (PRD §7.4, §18).
///
/// Tracks every request the host app issues through the supplied [Dio]
/// instance and contributes:
/// * an observation fragment of in-flight + recent completions
/// * a busy-state signal while requests are pending
/// * the `dio.cancel_in_flight` tool for adversarial testing
class ExplorationDioPlugin extends ExplorationPlugin {
  ExplorationDioPlugin(this._dio, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _interceptor = DioTrackingInterceptor(clock: clock);

  final Dio _dio;
  final DioTrackingInterceptor _interceptor;
  final DateTime Function() _clock;

  @override
  String get namespace => 'dio';

  @override
  List<ExplorationTool> get tools =>
      <ExplorationTool>[_CancelInFlightTool(_interceptor)];

  @override
  Future<void> initialize(PluginContext ctx) async {
    _dio.interceptors.add(_interceptor);
  }

  /// Heuristic: most requests resolve under ~600ms; clamp the tail at 100ms
  /// so callers don't see a zero/negative remaining estimate.
  int _estRemaining(int elapsedMs) => elapsedMs >= 600 ? 100 : 600 - elapsedMs;

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    final inFlight = _interceptor.inFlight.values.toList();
    final recent = _interceptor.recentCompleted;
    if (inFlight.isEmpty && recent.isEmpty) return null;

    final now = _clock();
    final frag = <String, Object?>{
      'in_flight': <Map<String, Object?>>[
        for (final t in inFlight)
          <String, Object?>{
            'id': t.id,
            'method': t.method,
            'host': t.host,
            'path': t.path,
            'elapsed_ms': t.elapsedMs(now),
            'est_remaining_ms': _estRemaining(t.elapsedMs(now)),
          },
      ],
      'recent_completed': <Map<String, Object?>>[
        for (final c in recent) c.toJson(),
      ],
    };
    return truncateToBudget(frag, kPluginBudgetBytes);
  }

  @override
  Future<BusyState> busyState() async {
    if (_interceptor.inFlight.isEmpty) return BusyState.idle;
    final n = _interceptor.inFlight.length;
    final now = _clock();
    var maxElapsed = 0;
    for (final t in _interceptor.inFlight.values) {
      final e = t.elapsedMs(now);
      if (e > maxElapsed) maxElapsed = e;
    }
    return BusyState(
      isBusy: true,
      reason: '$n in-flight requests',
      estimatedDuration: Duration(milliseconds: _estRemaining(maxElapsed)),
    );
  }

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {
    _dio.interceptors.remove(_interceptor);
  }
}

class _CancelInFlightTool extends ExplorationTool {
  _CancelInFlightTool(this._i);

  final DioTrackingInterceptor _i;

  @override
  String get name => 'cancel_in_flight';

  @override
  String get description =>
      'Cancel all currently in-flight Dio requests (adversarial testing).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async => ToolResult(
        ok: true,
        value: <String, Object?>{'cancelled': _i.cancelAll()},
      );
}
