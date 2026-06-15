/// Tests for the `requested`-namespace × handshake-manifest projection
/// that frontends hand to [DefaultLoopHost.fromSession]. Pure-Dart, no
/// `dart:io`. Mirrors `leonard_cli/test/extension_tools_test.dart`
/// (which now re-exports this same helper).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('buildExtensionTools', () {
    test('empty requested → empty map', () {
      final out = buildExtensionTools(
        requested: const <String>[],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>['go']),
        ],
      );
      expect(out, isEmpty);
    });

    test('intersects requested with handshake; descriptors per tool name', () {
      final out = buildExtensionTools(
        requested: const <String>['router', 'riverpod', 'dio'],
        handshake: const <ExtensionManifestEntry>[
          // Handshake carries BARE tool names; buildExtensionTools prefixes
          // the namespace to produce the qualified ToolDescriptor.name.
          ExtensionManifestEntry(
            namespace: 'router',
            tools: <String>['navigate'],
          ),
          ExtensionManifestEntry(
            namespace: 'riverpod',
            tools: <String>['invalidate_provider'],
          ),
          // No `dio` entry — handshake says it isn't loaded.
        ],
      );
      expect(out.keys, containsAll(<String>['router', 'riverpod']));
      expect(
        out.containsKey('dio'),
        isFalse,
        reason: 'unknown ns is dropped, not invented',
      );
      expect(out['router'], hasLength(1));
      expect(out['router']!.single.name, 'router.navigate');
      expect(out['riverpod']!.single.name, 'riverpod.invalidate_provider');
      expect(out['router']!.single.inputSchema['type'], 'object');
    });

    test('non-empty requested yields non-empty extensionTools (regression: '
        'panel must not silently wire const {} through)', () {
      final Map<String, List<ToolDescriptor>> out = buildExtensionTools(
        requested: const <String>['router'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(
            namespace: 'router',
            tools: <String>['go', 'back'],
          ),
        ],
      );
      expect(
        out,
        isNotEmpty,
        reason: 'a non-empty requested must produce a non-empty map',
      );
      expect(out['router'], hasLength(2));
      expect(out['router']!.map((t) => t.name).toList(), <String>[
        'router.go',
        'router.back',
      ]);
    });

    test('handshake namespace not in requested is excluded', () {
      final out = buildExtensionTools(
        requested: const <String>['router'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>['go']),
          ExtensionManifestEntry(
            namespace: 'dio',
            tools: <String>['cancel_in_flight'],
          ),
        ],
      );
      expect(out.keys, <String>['router']);
    });

    test('accepts a Set<String> for requested (Iterable contract)', () {
      final out = buildExtensionTools(
        requested: <String>{'router'},
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>['go']),
        ],
      );
      expect(out.keys, <String>['router']);
    });
  });

  group('unknownExtensionNamespaces', () {
    test('returns names requested but absent from handshake', () {
      final unknown = unknownExtensionNamespaces(
        requested: const <String>['router', 'typo', 'dio'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>[]),
        ],
      );
      expect(unknown, <String>['typo', 'dio']);
    });

    test('returns [] when every requested namespace is present', () {
      final unknown = unknownExtensionNamespaces(
        requested: const <String>['router'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>[]),
        ],
      );
      expect(unknown, isEmpty);
    });
  });
}
