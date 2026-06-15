import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:leonard_dio/leonard_dio.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/test_support/perception_serializer.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

class _HangingAdapter implements HttpClientAdapter {
  final Map<String, Completer<ResponseBody>> pending =
      <String, Completer<ResponseBody>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    final id = options.extra['_explorationDioId'] as String;
    final c = Completer<ResponseBody>();
    pending[id] = c;
    // Wire cancel: when cancelFuture fires, complete the response future
    // with an error so dio.get() rejects with a DioException.
    cancelFuture?.then((dynamic err) {
      if (!c.isCompleted) {
        c.completeError(err as Object);
      }
    });
    return c.future;
  }

  @override
  void close({bool force = false}) {}
}

(LeonardDioExtension, Dio, _HangingAdapter) _make() {
  final adapter = _HangingAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  final extension = LeonardDioExtension(dio);
  return (extension, dio, adapter);
}

Future<void> _init(LeonardDioExtension p) async {
  await p.initialize(
    ExtensionContext(namespace: 'dio', scheduler: SchedulerBinding.instance),
  );
}

/// Pump until [predicate] holds or the deadline expires; keeps tests
/// independent of arbitrary fixed delays.
Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('predicate never satisfied', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Harvest the dio extension's observation fragment via the perception path,
/// exactly as the binding's single observation loop does.
Map<String, Object?> _harvest(LeonardDioExtension extension) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(extension.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('namespace is dio and tool is cancel_in_flight', () async {
    final (p, _, _) = _make();
    await _init(p);
    expect(p.namespace, 'dio');
    expect(p.tools.single.name, 'cancel_in_flight');
  });

  test('isPerceptionIdle is true when idle', () async {
    final (p, _, _) = _make();
    await _init(p);
    expect(p.isPerceptionIdle(), isTrue);
  });

  test('busyState reports busy with reason while pending', () async {
    final (p, dio, adapter) = _make();
    await _init(p);
    unawaited(
      dio.get<dynamic>('https://api.example.com/x').catchError((Object _) {
        return Response<dynamic>(requestOptions: RequestOptions(path: ''));
      }),
    );
    await _pumpUntil(() => adapter.pending.isNotEmpty);
    final s = await p.busyState();
    expect(s.isBusy, isTrue);
    expect(s.reason, '1 in-flight requests');
    expect(s.estimatedDuration, isNotNull);
  });

  test('observation strips query strings from URLs', () async {
    final (p, dio, adapter) = _make();
    await _init(p);
    unawaited(
      dio.get<dynamic>('https://api.example.com/x?token=secret').catchError((
        Object _,
      ) {
        return Response<dynamic>(requestOptions: RequestOptions(path: ''));
      }),
    );
    await _pumpUntil(() => adapter.pending.isNotEmpty);
    expect(p.isPerceptionIdle(), isFalse);
    final frag = _harvest(p);
    final entry = (frag['in_flight']! as List).single as Map<String, Object?>;
    expect(entry['host'], 'api.example.com');
    expect(entry['path'], '/x');
    expect(entry.containsKey('id'), isTrue);
    expect(entry['method'], 'GET');
    expect(entry['elapsed_ms'], isA<int>());
    expect(entry['est_remaining_ms'], isA<int>());
    expect(jsonEncode(frag), isNot(contains('secret')));
  });

  test('busy clears once request completes', () async {
    final (p, dio, adapter) = _make();
    await _init(p);
    final f = dio.get<dynamic>('https://api.example.com/x').catchError((
      Object _,
    ) {
      return Response<dynamic>(requestOptions: RequestOptions(path: ''));
    });
    await _pumpUntil(() => adapter.pending.isNotEmpty);
    expect((await p.busyState()).isBusy, isTrue);

    adapter.pending.values.single.complete(
      ResponseBody.fromString(
        '{}',
        200,
        headers: <String, List<String>>{
          'content-type': <String>['application/json'],
        },
      ),
    );
    try {
      await f;
    } catch (_) {
      // ignore
    }
    expect((await p.busyState()).isBusy, isFalse);

    final frag = _harvest(p);
    final c =
        (frag['recent_completed']! as List).single as Map<String, Object?>;
    expect(c['status'], 200);
    expect(
      c.keys,
      containsAll(<String>[
        'id',
        'method',
        'host',
        'path',
        'status',
        'duration_ms',
      ]),
    );
  });

  test('cancel_in_flight tool cancels and returns count', () async {
    final (p, dio, adapter) = _make();
    await _init(p);
    final f = dio.get<dynamic>(
      'https://a.example.com/x',
      cancelToken: CancelToken(),
    );
    await _pumpUntil(() => adapter.pending.isNotEmpty);
    final r = await p.tools.single.call(const <String, Object?>{});
    expect(r.ok, isTrue);
    expect((r.value! as Map)['cancelled'], 1);
    await expectLater(f, throwsA(isA<DioException>()));
  });

  test('dispose removes interceptor', () async {
    final (p, dio, _) = _make();
    await _init(p);
    final before = dio.interceptors.length;
    await p.dispose();
    expect(dio.interceptors.length, before - 1);
  });
}
