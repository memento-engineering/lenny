import 'package:leonard_agent/leonard_agent.dart'
    show ExtensionManifestEntry;
import 'package:leonard_devtools/src/manifest_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManifestProbeResult', () {
    test('ManifestProbeLoading constructs', () {
      const r = ManifestProbeLoading();
      expect(r, isA<ManifestProbeResult>());
    });

    test('ManifestProbeLoaded round-trips plugins', () {
      const entries = [
        ExtensionManifestEntry(namespace: 'router', tools: ['router.go']),
        ExtensionManifestEntry(namespace: 'dio', tools: ['dio.respondNext']),
      ];
      const r = ManifestProbeLoaded(entries);
      expect(r.plugins, hasLength(2));
      expect(r.plugins.first.namespace, 'router');
      expect(r.plugins[1].tools, contains('dio.respondNext'));
    });

    test('ManifestProbeLoaded accepts empty list', () {
      const r = ManifestProbeLoaded(<ExtensionManifestEntry>[]);
      expect(r.plugins, isEmpty);
    });

    test('ManifestProbeBindingMissing constructs', () {
      const r = ManifestProbeBindingMissing();
      expect(r, isA<ManifestProbeResult>());
    });

    test('ManifestProbeFailed surfaces message', () {
      const r = ManifestProbeFailed('boom');
      expect(r.message, 'boom');
    });

    test('sealed switch covers every variant', () {
      const variants = <ManifestProbeResult>[
        ManifestProbeLoading(),
        ManifestProbeLoaded(<ExtensionManifestEntry>[]),
        ManifestProbeBindingMissing(),
        ManifestProbeFailed('x'),
      ];
      for (final v in variants) {
        final tag = switch (v) {
          ManifestProbeLoading() => 'loading',
          ManifestProbeLoaded() => 'loaded',
          ManifestProbeBindingMissing() => 'missing',
          ManifestProbeFailed() => 'failed',
        };
        expect(tag, isNotEmpty);
      }
    });
  });
}
