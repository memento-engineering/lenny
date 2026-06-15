import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Hand-rolled fake — overrides only [callServiceExtension].
class _FakeVmService extends VmService {
  _FakeVmService(this._handler) : super(const Stream<dynamic>.empty(), (_) {});

  final Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  )
  _handler;

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
    test('decodes protocolVersion and extension manifest', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{
          'protocolVersion': '2',
          'bindingType': 'LeonardBinding',
          'flutterMode': 'debug',
          'extensionCount': 1,
          'extensions': <Map<String, dynamic>>[
            <String, dynamic>{
              'namespace': 'router',
              'tools': <String>['go'],
            },
          ],
        }),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      final result = await client.handshake();

      expect(fake.lastMethod, equals('ext.exploration.core.handshake'));
      expect(fake.lastIsolateId, equals('iso-1'));
      expect(result.contractVersion, equals('2'));
      expect(result.extensions, hasLength(1));
      expect(result.extensions.first.namespace, equals('router'));
      expect(result.extensions.first.tools, equals(<String>['go']));
    });

    test(
      'handshake throws BindingNotInitializedError on RPC code -32601',
      () async {
        final fake = _FakeVmService((method, iso, args) async {
          throw RPCError('callServiceExtension', -32601, 'method not found');
        });
        final client = VmServiceClient.forTest(fake, 'iso-1');

        await expectLater(
          client.handshake(),
          throwsA(isA<BindingNotInitializedError>()),
        );
      },
    );

    test('handshake rethrows non-(-32601) RPCError unchanged', () async {
      final fake = _FakeVmService((method, iso, args) async {
        throw RPCError('callServiceExtension', 100, 'feature disabled');
      });
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await expectLater(client.handshake(), throwsA(isA<RPCError>()));
    });
  });

  group('VmServiceClient.executeAction / callExtension', () {
    test('routes plugin tool calls to ext.exploration.<ns>.<tool>', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{'ok': true}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      final act = await client.executeAction(
        'router.go',
        const <String, dynamic>{'route': '/home'},
      );
      expect(fake.lastMethod, equals('ext.exploration.router.go'));
      // Each arg value is JSON-encoded on the wire so the binding's
      // `_tryDecode` round-trips nested values.
      expect(fake.lastArgs?['route'], equals('"/home"'));
      expect(act, equals(<String, dynamic>{'ok': true}));
    });

    test('routes core tool calls to ext.exploration.core.<tool>', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{'ok': true}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await client.executeAction('core.tap', const <String, dynamic>{'id': 42});
      expect(fake.lastMethod, equals('ext.exploration.core.tap'));
      expect(fake.lastArgs?['id'], equals('42'));
    });

    test(
      'JSON-encodes nested values so the binding can _tryDecode them back',
      () async {
        final fake = _FakeVmService(
          (method, iso, args) async => _resp(<String, dynamic>{'ok': true}),
        );
        final client = VmServiceClient.forTest(fake, 'iso-1');

        await client.executeAction('forms.fill', const <String, dynamic>{
          'count': 42,
          'target': 'home',
          'payload': <String, dynamic>{'k': 1},
        });
        expect(fake.lastMethod, equals('ext.exploration.forms.fill'));
        expect(fake.lastArgs?['count'], equals('42'));
        expect(fake.lastArgs?['target'], equals('"home"'));
        expect(fake.lastArgs?['payload'], equals('{"k":1}'));
      },
    );

    test('throws ArgumentError on unqualified name (no dot)', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      expect(
        () => client.executeAction('tap', const <String, dynamic>{}),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'name')),
      );
      expect(fake.callCount, equals(0));
    });

    test('throws ArgumentError on leading-dot name', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      expect(
        () => client.executeAction('.tool', const <String, dynamic>{}),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.callCount, equals(0));
    });

    test('throws ArgumentError on trailing-dot name', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      expect(
        () => client.executeAction('core.', const <String, dynamic>{}),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.callCount, equals(0));
    });

    test('callExtension passes the literal extension name through', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{'echo': method}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await client.callExtension(
        'ext.exploration.router.snapshot',
        const <String, dynamic>{},
      );
      expect(fake.lastMethod, equals('ext.exploration.router.snapshot'));
    });

    test('non-handshake extensions do NOT translate code -32601', () async {
      final fake = _FakeVmService((method, iso, args) async {
        throw RPCError('callServiceExtension', -32601, 'method not found');
      });
      final client = VmServiceClient.forTest(fake, 'iso-1');

      await expectLater(
        client.executeAction('router.go', const <String, dynamic>{}),
        throwsA(isA<RPCError>()),
      );
    });
  });
}
