import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A [HttpClientAdapter] that returns canned JSON responses for the
/// sample app's endpoints. No real network is ever opened.
///
/// Endpoints:
///   POST /auth/login   — `demo@example.com` / `password` returns 200+token,
///                        anything else returns 401 invalid_credentials.
///   GET  /profile      — returns the demo user's profile.
///   PUT  /profile      — accepts any body, returns ok.
///   GET  /items        — returns 12 canned items.
///   PUT  /settings     — accepts any body, returns ok.
///
/// Anything else returns 404. Each call sleeps for [latency] before
/// responding to simulate a real backend.
class FakeApiAdapter implements HttpClientAdapter {
  FakeApiAdapter({this.latency = const Duration(milliseconds: 250)});

  final Duration latency;

  /// Extra per-endpoint latency on top of [latency], used by the gauntlet's
  /// settle scenarios to make in-flight `dio` work observable for long
  /// enough to stress the stability policy.
  static const Map<String, Duration> _scenarioLatency = <String, Duration>{
    'GET /confirmation': Duration(milliseconds: 1300),
    'POST /like': Duration(milliseconds: 550),
    'GET /search': Duration(milliseconds: 350),
  };

  /// Deterministic result counts for the debounced-search scenario, keyed by
  /// the `q` query parameter. The fixture's ground-truth oracle relies on
  /// these being stable.
  static const Map<String, int> _searchCounts = <String, int>{
    'widget': 5,
    'alpha': 3,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(latency);
    final key = '${options.method} ${options.path}';
    final Duration? extra = _scenarioLatency[key];
    if (extra != null) await Future<void>.delayed(extra);
    switch (key) {
      // ── Gauntlet settle scenarios ──────────────────────────────────
      case 'GET /confirmation':
        return _json(200, <String, Object?>{'code': 'AZ-4471'});
      case 'POST /like':
        // Always reconciles to NOT liked — the server "rejects" the
        // optimistic like, so the settled state disagrees with the flash.
        return _json(200, <String, Object?>{'liked': false});
      case 'GET /search':
        final String q = (options.queryParameters['q'] ?? '').toString();
        final int n = _searchCounts[q] ?? 0;
        return _json(200, <String, Object?>{
          'results': <Map<String, Object?>>[
            for (var i = 0; i < n; i++)
              <String, Object?>{'id': '$q-$i', 'title': '$q result ${i + 1}'},
          ],
        });
      case 'POST /auth/login':
        final raw = await _readAll(requestStream);
        final decoded = raw.isEmpty
            ? <String, Object?>{}
            : jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
        if (decoded['email'] == 'demo@example.com' &&
            decoded['password'] == 'password') {
          return _json(200, <String, Object?>{
            'token': 'fake-token',
            'user': <String, Object?>{'id': 'u1', 'name': 'Demo'},
          });
        }
        return _json(401, <String, Object?>{'error': 'invalid_credentials'});
      case 'GET /profile':
        return _json(200, <String, Object?>{
          'id': 'u1',
          'name': 'Demo',
          'email': 'demo@example.com',
        });
      case 'PUT /profile':
        return _json(200, <String, Object?>{'ok': true});
      case 'GET /items':
        return _json(200, <String, Object?>{
          'items': <Map<String, Object?>>[
            for (var i = 0; i < 12; i++)
              <String, Object?>{'id': 'i$i', 'title': 'Item $i'},
          ],
        });
      case 'PUT /settings':
        return _json(200, <String, Object?>{'ok': true});
    }
    return _json(404, <String, Object?>{'error': 'not_found'});
  }

  Future<List<int>> _readAll(Stream<Uint8List>? stream) async {
    if (stream == null) return <int>[];
    return stream.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
  }

  ResponseBody _json(int statusCode, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: <String, List<String>>{
      'content-type': <String>['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}
