/// Regression test: the DevTools Prompt tab must load its
/// extension manifest by reusing an already-connected `VmService` (via
/// `probeManifest` → `VmServiceClient.fromVmService`), never by opening
/// its own `vm_service_io` connection — which crashes on web with
/// `Unsupported operation: Platform._version`.
library;

import 'package:leonard_agent/leonard_agent.dart'
    show BindingNotInitializedError, LeonardSession, ExtensionManifestEntry;
import 'package:leonard_devtools/src/leonard_shell.dart';
import 'package:leonard_devtools/src/manifest_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

/// Hand-rolled fake `VmService` — answers the handshake extension with
/// one extension and overrides nothing else.
class _FakeVmService extends VmService {
  _FakeVmService() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    expect(method, equals('ext.exploration.core.handshake'));
    final r = Response();
    r.json = <String, dynamic>{
      'contractVersion': '1.0.0',
      'extensions': <Map<String, dynamic>>[
        <String, dynamic>{
          'namespace': 'router',
          'tools': <String>['router.go'],
        },
      ],
    };
    return r;
  }

  @override
  Future<void> dispose() async {}
}

Future<LeonardSession> _noSession() async =>
    throw StateError('no session in this test');

void main() {
  testWidgets(
    'manifest probe built from probeManifest(fakeVmService, id) loads '
    'the extension manifest — no vm_service_io',
    (tester) async {
      final fake = _FakeVmService();
      Future<List<ExtensionManifestEntry>> probe() =>
          probeManifest(fake, 'iso-1');

      await tester.pumpWidget(
        MaterialApp(
          home: LeonardShell(manifestProbe: probe, sessionFactory: _noSession),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prompt.plugin.router')), findsOneWidget);
      expect(find.byKey(const Key('prompt.bindingNotDetected')), findsNothing);
    },
  );

  testWidgets('null-service probe closure yields ManifestProbeBindingMissing', (
    tester,
  ) async {
    Future<List<ExtensionManifestEntry>> probe() async {
      const VmService? vm = null;
      // ignore: dead_code
      if (vm == null) throw BindingNotInitializedError();
      // ignore: dead_code
      return probeManifest(vm, 'iso-1');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(manifestProbe: probe, sessionFactory: _noSession),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsOneWidget);
  });
}
