import 'dart:collection';

import 'package:dio/dio.dart';

import 'tracked_request.dart';

/// Dio interceptor that tracks every request the host app issues, exposing
/// in-flight and a small ring buffer of recent completions.
class DioTrackingInterceptor extends Interceptor {
  DioTrackingInterceptor({DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  static const int _ringSize = 8;
  static const String _idKey = '_explorationDioId';

  final Map<String, TrackedRequest> _inFlight = <String, TrackedRequest>{};
  final Queue<CompletedRequest> _completed = Queue<CompletedRequest>();
  final DateTime Function() _now;
  int _seq = 0;

  /// Read-only view of in-flight requests keyed by id.
  UnmodifiableMapView<String, TrackedRequest> get inFlight =>
      UnmodifiableMapView<String, TrackedRequest>(_inFlight);

  /// Read-only snapshot of recent completions (oldest first).
  List<CompletedRequest> get recentCompleted =>
      List<CompletedRequest>.unmodifiable(_completed);

  String _idFor(RequestOptions o) {
    final existing = o.extra[_idKey];
    if (existing is String) return existing;
    final id = 'req_${_seq++}';
    o.extra[_idKey] = id;
    return id;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = _idFor(options);
    _inFlight[id] = TrackedRequest(
      id: id,
      method: options.method.toUpperCase(),
      host: options.uri.host,
      path: options.uri.path,
      startedAt: _now(),
      cancelToken: options.cancelToken,
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _complete(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _complete(err.requestOptions, err.response?.statusCode);
    handler.next(err);
  }

  void _complete(RequestOptions opts, int? status) {
    final id = opts.extra[_idKey];
    if (id is! String) return;
    final tracked = _inFlight.remove(id);
    if (tracked == null) return;
    _completed.addLast(
      CompletedRequest(
        id: tracked.id,
        method: tracked.method,
        host: tracked.host,
        path: tracked.path,
        status: status,
        durationMs: tracked.elapsedMs(_now()),
      ),
    );
    while (_completed.length > _ringSize) {
      _completed.removeFirst();
    }
  }

  /// Cancel every tracked in-flight request via its [CancelToken]. Returns
  /// the number of requests that were in-flight at call time.
  int cancelAll() {
    final n = _inFlight.length;
    for (final t in _inFlight.values) {
      try {
        t.cancelToken?.cancel('leonard_dio.cancel_in_flight');
      } catch (_) {
        // Best-effort cancellation; swallow per-token failures.
      }
    }
    return n;
  }
}
