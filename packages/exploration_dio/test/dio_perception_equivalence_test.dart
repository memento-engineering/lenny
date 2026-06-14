library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploration_dio/exploration_dio.dart';
import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/test_support/observation_equivalence.dart';
import 'package:exploration_flutter/test_support/perception_serializer.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

class _HangingAdapter implements HttpClientAdapter {
  final Map<String, Completer<ResponseBody>> pending =
      <String, Completer<ResponseBody>>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) {
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

Map<String, Object?> _harvestFragment(ExplorationDioPlugin plugin) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(plugin.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

Map<String, Object?> _wrapObs(Map<String, Object?> dioFrag) =>
    <String, Object?>{
      'semantics': <Object?>[],
      'routes': <Object?>[],
      'errors': <Object?>[],
      'stability': <String, Object?>{},
      'plugins': <String, Object?>{'dio': dioFrag},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ObservationContext kCtx =
      ObservationContext(turn: 0, sinceLastAction: Duration.zero);

  test('completed request: perception fragment equals legacy fragment',
      () async {
    final _HangingAdapter adapter = _HangingAdapter();
    final Dio testDio = Dio()..httpClientAdapter = adapter;
    final ExplorationDioPlugin plugin = ExplorationDioPlugin(testDio);
    await plugin.initialize(
      PluginContext(namespace: 'dio', scheduler: SchedulerBinding.instance),
    );

    final Future<Response<dynamic>> req =
        testDio.get<dynamic>('https://api.example.com/users').catchError(
      (Object _) => Response<dynamic>(
        requestOptions: RequestOptions(path: ''),
      ),
    );

    await _pumpUntil(() => adapter.pending.isNotEmpty);
    expect(adapter.pending, hasLength(1));

    adapter.pending.values.first.complete(
      ResponseBody.fromString('{"data":[]}', 200),
    );
    try {
      await req;
    } catch (_) {}

    final Map<String, Object?>? legacy = await plugin.observe(kCtx);
    expect(legacy, isNotNull,
        reason: 'legacy observe() must emit with a completed request');

    final Map<String, Object?> perceptionFrag = _harvestFragment(plugin);

    assertObservationEquivalent(
      _wrapObs(legacy!),
      _wrapObs(perceptionFrag),
    );

    await plugin.dispose();
  });
}
