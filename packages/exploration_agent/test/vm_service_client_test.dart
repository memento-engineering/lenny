import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Hand-rolled fake — overrides only [callServiceExtension].
class _FakeVmService extends VmService {
  _FakeVmService(this._handler)
      : super(
          const Stream<dynamic>.empty(),
          (_) {},
        );

  final Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  ) _handler;

  int callCount = 0;
  String? lastMethod;
  String? lastIsolateId;
  Map<String, dynamic>? lastArgs;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) {
    callCount++;
    lastMethod = method;
    lastIsolateId = isolateId;
    lastArgs = args;
    return _handler(method, isolateId, args);
  }

  @override
  Future<void> dispose() async {}
}

Response _resp(Map<String, dynamic> json) {
  final r = Response();
  r.json = json;
  return r;
}

void main() {
  group('VmServiceClient.handshake', () {
    test('decodes protocolVersion and plugin manifest', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{
          'protocolVersion': '1',
          'bindingType': 'ExplorationBinding',
          'flutterMode': 'debug',
          'pluginCount': 1,
          'plugins': <Map<String, dynamic>>[
            <String, dynamic>{
              'namespace': 'router',
              'tools': <String>['go'],
            },
          ],
        }),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      final result = await client.handshake();

      expect(fake.lastMethod,
          equals('ext.flutter.exploration.core.handshake'));
      expect(fake.lastIsolateId, equals('iso-1'));
      expect(result.contractVersion, equals('1'));
      expect(result.plugins, hasLength(1));
      expect(result.plugins.first.namespace, equals('router'));
      expect(result.plugins.first.tools, equals(<String>['go']));
    });

    test('handshake throws BindingNotInitializedError on RPC code -32601',
        () async {
      final fake = _FakeVmService(
        (method, iso, args) async {
          throw RPCError('callServiceExtension', -32601, 'method not found');
        },
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await expectLater(
        client.handshake(),
        throwsA(isA<BindingNotInitializedError>()),
      );
    });

    test('handshake rethrows non-(-32601) RPCError unchanged', () async {
      final fake = _FakeVmService(
        (method, iso, args) async {
          throw RPCError('callServiceExtension', 100, 'feature disabled');
        },
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await expectLater(client.handshake(), throwsA(isA<RPCError>()));
    });
  });

  group('VmServiceClient.executeAction / callExtension', () {
    test('routes executeAction to the core extension with the correct args',
        () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{'ok': true}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      final act = await client.executeAction(
        'router.go',
        const <String, dynamic>{'route': '/home'},
      );
      expect(
        fake.lastMethod,
        equals('ext.flutter.exploration.core.executeAction'),
      );
      expect(fake.lastArgs?['name'], equals('router.go'));
      expect(
        fake.lastArgs?['args'],
        equals(<String, dynamic>{'route': '/home'}),
      );
      expect(act, equals(<String, dynamic>{'ok': true}));
    });

    test('callExtension passes the literal extension name through',
        () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{'echo': method}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await client.callExtension(
        'ext.flutter.exploration.router.snapshot',
        const <String, dynamic>{},
      );
      expect(
        fake.lastMethod,
        equals('ext.flutter.exploration.router.snapshot'),
      );
    });

    test('non-handshake extensions do NOT translate code -32601', () async {
      final fake = _FakeVmService(
        (method, iso, args) async {
          throw RPCError('callServiceExtension', -32601, 'method not found');
        },
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await expectLater(
        client.executeAction('router.go', const <String, dynamic>{}),
        throwsA(isA<RPCError>()),
      );
    });
  });
}
