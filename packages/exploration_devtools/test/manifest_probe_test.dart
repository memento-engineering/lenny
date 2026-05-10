import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry;
import 'package:exploration_devtools/src/manifest_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManifestProbeResult', () {
    test('ManifestProbeLoading constructs', () {
      const r = ManifestProbeLoading();
      expect(r, isA<ManifestProbeResult>());
    });

    test('ManifestProbeLoaded round-trips plugins', () {
      const entries = [
        PluginManifestEntry(namespace: 'router', tools: ['router.go']),
        PluginManifestEntry(namespace: 'dio', tools: ['dio.respondNext']),
      ];
      const r = ManifestProbeLoaded(entries);
      expect(r.plugins, hasLength(2));
      expect(r.plugins.first.namespace, 'router');
      expect(r.plugins[1].tools, contains('dio.respondNext'));
    });

    test('ManifestProbeLoaded accepts empty list', () {
      const r = ManifestProbeLoaded(<PluginManifestEntry>[]);
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
        ManifestProbeLoaded(<PluginManifestEntry>[]),
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
