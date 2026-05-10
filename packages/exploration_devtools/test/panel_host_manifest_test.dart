import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show BindingNotInitializedError, PluginManifestEntry;
import 'package:exploration_devtools/src/manifest_probe.dart';
import 'package:exploration_devtools/src/panel_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeRecorder {
  int calls = 0;
  ManifestProbe wrap(ManifestProbe inner) {
    return (Uri u) {
      calls += 1;
      return inner(u);
    };
  }
}

Widget _host({
  required VmServiceUriResolver vmServiceUri,
  required ManifestProbe probe,
  GlobalKey<ExplorationPanelHostState>? hostKey,
}) {
  return MaterialApp(
    home: ExplorationPanelHost(
      key: hostKey,
      vmServiceUri: vmServiceUri,
      manifestProbe: probe,
      child: const SizedBox.shrink(),
    ),
  );
}

void main() {
  testWidgets('initState triggers refreshManifest', (tester) async {
    final hostKey = GlobalKey<ExplorationPanelHostState>();
    final recorder = _ProbeRecorder();
    final probe = recorder.wrap((_) async => const [
          PluginManifestEntry(namespace: 'router', tools: ['router.go']),
        ]);

    await tester.pumpWidget(_host(
      vmServiceUri: () => 'ws://localhost:9999/abc/',
      probe: probe,
      hostKey: hostKey,
    ));
    await tester.pumpAndSettle();

    expect(recorder.calls, 1);
    final value = hostKey.currentState!.manifest.value;
    expect(value, isA<ManifestProbeLoaded>());
    expect((value as ManifestProbeLoaded).plugins, hasLength(1));
    expect(value.plugins.first.namespace, 'router');
  });

  testWidgets('null vmServiceUri publishes ManifestProbeBindingMissing',
      (tester) async {
    final hostKey = GlobalKey<ExplorationPanelHostState>();
    final recorder = _ProbeRecorder();
    final probe = recorder.wrap((_) async => const <PluginManifestEntry>[]);

    await tester.pumpWidget(_host(
      vmServiceUri: () => null,
      probe: probe,
      hostKey: hostKey,
    ));
    await tester.pumpAndSettle();

    expect(recorder.calls, 0);
    expect(
      hostKey.currentState!.manifest.value,
      isA<ManifestProbeBindingMissing>(),
    );
  });

  testWidgets(
      'BindingNotInitializedError publishes ManifestProbeBindingMissing',
      (tester) async {
    final hostKey = GlobalKey<ExplorationPanelHostState>();
    Future<List<PluginManifestEntry>> probe(Uri _) async {
      throw BindingNotInitializedError();
    }

    await tester.pumpWidget(_host(
      vmServiceUri: () => 'ws://localhost:9999/abc/',
      probe: probe,
      hostKey: hostKey,
    ));
    await tester.pumpAndSettle();

    expect(
      hostKey.currentState!.manifest.value,
      isA<ManifestProbeBindingMissing>(),
    );
  });

  testWidgets('arbitrary throw publishes ManifestProbeFailed with message',
      (tester) async {
    final hostKey = GlobalKey<ExplorationPanelHostState>();
    Future<List<PluginManifestEntry>> probe(Uri _) async {
      throw StateError('boom');
    }

    await tester.pumpWidget(_host(
      vmServiceUri: () => 'ws://localhost:9999/abc/',
      probe: probe,
      hostKey: hostKey,
    ));
    await tester.pumpAndSettle();

    final v = hostKey.currentState!.manifest.value;
    expect(v, isA<ManifestProbeFailed>());
    expect((v as ManifestProbeFailed).message, contains('boom'));
  });

  testWidgets('concurrent refreshManifest only publishes latest',
      (tester) async {
    final hostKey = GlobalKey<ExplorationPanelHostState>();
    final completerA = Completer<List<PluginManifestEntry>>();
    var useProbeA = true;
    Future<List<PluginManifestEntry>> probe(Uri _) async {
      if (useProbeA) return completerA.future;
      return const [
        PluginManifestEntry(namespace: 'dio', tools: ['dio.respondNext']),
      ];
    }

    await tester.pumpWidget(_host(
      vmServiceUri: () => 'ws://localhost:9999/abc/',
      probe: probe,
      hostKey: hostKey,
    ));
    // First probe is gated on completerA. Verify it's loading.
    await tester.pump();
    expect(hostKey.currentState!.manifest.value, isA<ManifestProbeLoading>());

    // Swap to probe B and trigger second refresh.
    useProbeA = false;
    // ignore: unawaited_futures
    hostKey.currentState!.refreshManifest();
    await tester.pumpAndSettle();

    // B has already resolved.
    final v = hostKey.currentState!.manifest.value;
    expect(v, isA<ManifestProbeLoaded>());
    expect((v as ManifestProbeLoaded).plugins.single.namespace, 'dio');

    // Late completion of A must NOT clobber B.
    completerA.complete(const [
      PluginManifestEntry(namespace: 'router', tools: ['router.go']),
    ]);
    await tester.pumpAndSettle();

    final after = hostKey.currentState!.manifest.value;
    expect(after, isA<ManifestProbeLoaded>());
    expect((after as ManifestProbeLoaded).plugins.single.namespace, 'dio');
  });
}
