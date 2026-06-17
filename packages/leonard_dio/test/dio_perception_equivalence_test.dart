library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:leonard_dio/leonard_dio.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/test_support/perception_serializer.dart';
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
    final String id = options.extra['_explorationDioId'] as String;
    final Completer<ResponseBody> c = Completer<ResponseBody>();
    pending[id] = c;
    return c.future;
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('predicate never satisfied', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Map<String, Object?> _harvestFragment(LeonardDioExtension extension) {
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

  test(
    'completed request: perception fragment surfaces the completion',
    () async {
      final _HangingAdapter adapter = _HangingAdapter();
      final Dio testDio = Dio()..httpClientAdapter = adapter;
      final LeonardDioExtension extension = LeonardDioExtension(testDio);
      await extension.initialize(
        ExtensionContext(namespace: 'dio'),
      );

      final Future<Response<dynamic>> req = testDio
          .get<dynamic>('https://api.example.com/users')
          .catchError(
            (Object _) =>
                Response<dynamic>(requestOptions: RequestOptions(path: '')),
          );

      await _pumpUntil(() => adapter.pending.isNotEmpty);
      expect(adapter.pending, hasLength(1));

      adapter.pending.values.first.complete(
        ResponseBody.fromString('{"data":[]}', 200),
      );
      try {
        await req;
      } catch (_) {}

      // The extension is no longer idle once a request completes.
      expect(extension.isPerceptionIdle(), isFalse);

      final Map<String, Object?> perceptionFrag = _harvestFragment(extension);
      expect(perceptionFrag['in_flight'], isEmpty);
      final Map<String, Object?> completed =
          (perceptionFrag['recent_completed']! as List).single
              as Map<String, Object?>;
      expect(completed['host'], 'api.example.com');
      expect(completed['path'], '/users');
      expect(completed['status'], 200);

      await extension.dispose();
    },
  );

  test(
    'idle state: isPerceptionIdle() is true (binding suppresses the ns)',
    () async {
      final _HangingAdapter adapter = _HangingAdapter();
      final Dio testDio = Dio()..httpClientAdapter = adapter;
      final LeonardDioExtension extension = LeonardDioExtension(testDio);
      await extension.initialize(
        ExtensionContext(namespace: 'dio'),
      );

      // No requests sent — extension is completely idle. The binding's
      // isPerceptionIdle() gate (reproducing the retired observe()==null)
      // suppresses the dio namespace entirely.
      expect(extension.isPerceptionIdle(), isTrue);
      expect(adapter.pending, isEmpty);
      await extension.dispose();
    },
  );
}
