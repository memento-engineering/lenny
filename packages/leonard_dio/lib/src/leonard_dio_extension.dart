import 'dart:async';

import 'package:dio/dio.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:genesis_perception/genesis_perception.dart';

import 'dio_perception.dart';
import 'dio_tracking_interceptor.dart';

/// Reference plugin for `package:dio` (PRD §7.4, §18).
///
/// Tracks every request the host app issues through the supplied [Dio]
/// instance and contributes:
/// * an observation fragment of in-flight + recent completions
/// * a busy-state signal while requests are pending
/// * the `dio.cancel_in_flight` tool for adversarial testing
class LeonardDioExtension extends LeonardExtension with PerceptionExtension {
  LeonardDioExtension(this._dio, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _interceptor = DioTrackingInterceptor(clock: clock);

  final Dio _dio;
  final DioTrackingInterceptor _interceptor;
  final DateTime Function() _clock;

  @override
  String get namespace => 'dio';

  @override
  List<LeonardTool> get tools =>
      <LeonardTool>[_CancelInFlightTool(_interceptor)];

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    _dio.interceptors.add(_interceptor);
  }

  /// Heuristic: most requests resolve under ~600ms; clamp the tail at 100ms
  /// so callers don't see a zero/negative remaining estimate.
  int _estRemaining(int elapsedMs) => elapsedMs >= 600 ? 100 : 600 - elapsedMs;

  @override
  bool isPerceptionIdle() =>
      _interceptor.inFlight.isEmpty && _interceptor.recentCompleted.isEmpty;

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

  @override
  Seed buildPerception() => DioPerception(_interceptor, _clock);
}

class _CancelInFlightTool extends LeonardTool {
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
