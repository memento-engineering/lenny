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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(latency);
    final key = '${options.method} ${options.path}';
    switch (key) {
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
    return stream.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
  }

  ResponseBody _json(int statusCode, Object body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: <String, List<String>>{
          'content-type': <String>['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
