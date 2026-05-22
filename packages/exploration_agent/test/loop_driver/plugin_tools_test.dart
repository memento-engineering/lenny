/// Tests for the `requested`-namespace × handshake-manifest projection
/// that frontends hand to [DefaultLoopHost.fromSession]. Pure-Dart, no
/// `dart:io`. Mirrors `exploration_cli/test/plugin_tools_test.dart`
/// (which now re-exports this same helper).
library;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

void main() {
  group('buildPluginTools', () {
    test('empty requested → empty map', () {
      final out = buildPluginTools(
        requested: const <String>[],
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(namespace: 'router', tools: <String>['go']),
        ],
      );
      expect(out, isEmpty);
    });

    test('intersects requested with handshake; descriptors per tool name',
        () {
      final out = buildPluginTools(
        requested: const <String>['router', 'riverpod', 'dio'],
        handshake: const <PluginManifestEntry>[
          // Handshake carries BARE tool names; buildPluginTools prefixes
          // the namespace to produce the qualified ToolDescriptor.name.
          PluginManifestEntry(
            namespace: 'router',
            tools: <String>['navigate'],
          ),
          PluginManifestEntry(
            namespace: 'riverpod',
            tools: <String>['invalidate_provider'],
          ),
          // No `dio` entry — handshake says it isn't loaded.
        ],
      );
      expect(out.keys, containsAll(<String>['router', 'riverpod']));
      expect(out.containsKey('dio'), isFalse,
          reason: 'unknown ns is dropped, not invented');
      expect(out['router'], hasLength(1));
      expect(out['router']!.single.name, 'router.navigate');
      expect(out['riverpod']!.single.name, 'riverpod.invalidate_provider');
      expect(out['router']!.single.inputSchema['type'], 'object');
    });

    test('non-empty requested yields non-empty pluginTools (regression: '
        'panel must not silently wire const {} through)', () {
      final Map<String, List<ToolDescriptor>> out = buildPluginTools(
        requested: const <String>['router'],
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(
            namespace: 'router',
            tools: <String>['go', 'back'],
          ),
        ],
      );
      expect(out, isNotEmpty,
          reason: 'a non-empty requested must produce a non-empty map');
      expect(out['router'], hasLength(2));
      expect(
        out['router']!.map((t) => t.name).toList(),
        <String>['router.go', 'router.back'],
      );
    });

    test('handshake namespace not in requested is excluded', () {
      final out = buildPluginTools(
        requested: const <String>['router'],
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(
            namespace: 'router',
            tools: <String>['go'],
          ),
          PluginManifestEntry(
            namespace: 'dio',
            tools: <String>['cancel_in_flight'],
          ),
        ],
      );
      expect(out.keys, <String>['router']);
    });

    test('accepts a Set<String> for requested (Iterable contract)', () {
      final out = buildPluginTools(
        requested: <String>{'router'},
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(
            namespace: 'router',
            tools: <String>['go'],
          ),
        ],
      );
      expect(out.keys, <String>['router']);
    });
  });

  group('unknownPluginNamespaces', () {
    test('returns names requested but absent from handshake', () {
      final unknown = unknownPluginNamespaces(
        requested: const <String>['router', 'typo', 'dio'],
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(namespace: 'router', tools: <String>[]),
        ],
      );
      expect(unknown, <String>['typo', 'dio']);
    });

    test('returns [] when every requested namespace is present', () {
      final unknown = unknownPluginNamespaces(
        requested: const <String>['router'],
        handshake: const <PluginManifestEntry>[
          PluginManifestEntry(namespace: 'router', tools: <String>[]),
        ],
      );
      expect(unknown, isEmpty);
    });
  });
}
