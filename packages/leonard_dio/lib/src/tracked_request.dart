import 'package:dio/dio.dart';

/// Snapshot of a Dio request that is currently in-flight.
class TrackedRequest {
  TrackedRequest({
    required this.id,
    required this.method,
    required this.host,
    required this.path,
    required this.startedAt,
    this.cancelToken,
  });

  final String id;
  final String method;
  final String host;
  final String path;
  final DateTime startedAt;
  final CancelToken? cancelToken;

  int elapsedMs(DateTime now) => now.difference(startedAt).inMilliseconds;
}

/// Snapshot of a Dio request that has completed (success or error).
class CompletedRequest {
  CompletedRequest({
    required this.id,
    required this.method,
    required this.host,
    required this.path,
    required this.durationMs,
    this.status,
  });

  final String id;
  final String method;
  final String host;
  final String path;
  final int? status;
  final int durationMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'method': method,
    'host': host,
    'path': path,
    'status': status,
    'duration_ms': durationMs,
  };
}
