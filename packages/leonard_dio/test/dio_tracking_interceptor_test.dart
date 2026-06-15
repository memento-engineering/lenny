import 'dart:async';

import 'package:dio/dio.dart';
import 'package:leonard_dio/src/dio_tracking_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCancelToken extends CancelToken {
  int cancelCalls = 0;
  Object? lastReason;

  @override
  void cancel([Object? reason]) {
    cancelCalls++;
    lastReason = reason;
    super.cancel(reason);
  }
}

class _FakeRequestHandler extends RequestInterceptorHandler {}

class _FakeResponseHandler extends ResponseInterceptorHandler {}

class _FakeErrorHandler extends ErrorInterceptorHandler {}

RequestOptions _opts({
  String method = 'GET',
  String url = 'https://api.example.com/x',
  CancelToken? cancelToken,
}) =>
    RequestOptions(path: url, method: method, cancelToken: cancelToken);

void main() {
  test('id is assigned on first request and reused on completion', () {
    final i = DioTrackingInterceptor();
    final o = _opts();
    i.onRequest(o, _FakeRequestHandler());
    final id = o.extra['_explorationDioId'];
    expect(id, isA<String>());
    expect(i.inFlight.length, 1);
    expect(i.inFlight.containsKey(id), isTrue);

    i.onResponse(
      Response<dynamic>(requestOptions: o, statusCode: 200),
      _FakeResponseHandler(),
    );
    expect(i.inFlight, isEmpty);
    expect(i.recentCompleted.single.id, id);
    expect(i.recentCompleted.single.status, 200);
  });

  test('in-flight count goes 0->1->0 across the response path', () {
    final i = DioTrackingInterceptor();
    expect(i.inFlight.length, 0);
    final o = _opts();
    i.onRequest(o, _FakeRequestHandler());
    expect(i.inFlight.length, 1);
    i.onResponse(
      Response<dynamic>(requestOptions: o, statusCode: 204),
      _FakeResponseHandler(),
    );
    expect(i.inFlight.length, 0);
  });

  test('error path also clears in-flight and records status if present',
      () async {
    final i = DioTrackingInterceptor();
    final o = _opts();
    i.onRequest(o, _FakeRequestHandler());
    expect(i.inFlight.length, 1);
    final err = DioException(
      requestOptions: o,
      response: Response<dynamic>(requestOptions: o, statusCode: 500),
      type: DioExceptionType.badResponse,
    );
    // ErrorInterceptorHandler.next() rejects the internal completer; run in
    // a guarded zone so the unhandled rejection doesn't fail the test.
    await runZonedGuarded(() async {
      i.onError(err, _FakeErrorHandler());
    }, (_, __) {});
    expect(i.inFlight.length, 0);
    expect(i.recentCompleted.single.status, 500);
  });

  test('ring buffer caps recent completions at 8', () {
    final i = DioTrackingInterceptor();
    for (var n = 0; n < 10; n++) {
      final o = _opts(url: 'https://h.example.com/n$n');
      i.onRequest(o, _FakeRequestHandler());
      i.onResponse(
        Response<dynamic>(requestOptions: o, statusCode: 200),
        _FakeResponseHandler(),
      );
    }
    expect(i.inFlight.length, 0);
    expect(i.recentCompleted.length, 8);
    // Oldest two ('n0','n1') were evicted; first remaining is n2.
    expect(i.recentCompleted.first.path, '/n2');
    expect(i.recentCompleted.last.path, '/n9');
  });

  test('cancelAll cancels each tracked CancelToken and returns N', () {
    final i = DioTrackingInterceptor();
    final t1 = _FakeCancelToken();
    final t2 = _FakeCancelToken();
    final o1 = _opts(cancelToken: t1);
    final o2 = _opts(cancelToken: t2, url: 'https://b.example.com/y');
    i.onRequest(o1, _FakeRequestHandler());
    i.onRequest(o2, _FakeRequestHandler());

    final n = i.cancelAll();
    expect(n, 2);
    expect(t1.cancelCalls, 1);
    expect(t2.cancelCalls, 1);
    expect(t1.lastReason, 'leonard_dio.cancel_in_flight');
  });
}
