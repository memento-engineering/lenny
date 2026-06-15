/// Tests for the `--extensions`-to-`extensionTools` projection that the CLI
/// hands to [DefaultLoopHost.fromSession]. Pure-Dart, no `dart:io`.
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_cli/src/extension_tools.dart';
import 'package:test/test.dart';

void main() {
  group('buildExtensionTools', () {
    test('empty --extensions → empty map', () {
      final out = buildExtensionTools(
        requested: const <String>[],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(namespace: 'router', tools: <String>['go']),
        ],
      );
      expect(out, isEmpty);
    });

    test('intersects requested with handshake; descriptors per tool name',
        () {
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
      expect(out.containsKey('dio'), isFalse,
          reason: 'unknown ns is dropped, not invented');
      expect(out['router'], hasLength(1));
      expect(out['router']!.single.name, 'router.navigate');
      expect(out['riverpod']!.single.name, 'riverpod.invalidate_provider');
      // Permissive object schema so the model can call the tool;
      // binding-side ActionValidator (cx6.17) is the authoritative check.
      expect(out['router']!.single.inputSchema['type'], 'object');
    });

    test('non-empty --extensions yields non-empty extensionTools reaching host '
        '(regression: the prior build wired const {} through)', () {
      final Map<String, List<ToolDescriptor>> out = buildExtensionTools(
        requested: const <String>['router'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(
            namespace: 'router',
            tools: <String>['go', 'back'],
          ),
        ],
      );
      expect(out, isNotEmpty,
          reason: 'a non-empty --extensions must produce a non-empty map');
      expect(out['router'], hasLength(2));
      expect(
        out['router']!.map((t) => t.name).toList(),
        <String>['router.go', 'router.back'],
      );
    });

    test('handshake namespace not in --extensions is excluded', () {
      final out = buildExtensionTools(
        requested: const <String>['router'],
        handshake: const <ExtensionManifestEntry>[
          ExtensionManifestEntry(
            namespace: 'router',
            tools: <String>['go'],
          ),
          ExtensionManifestEntry(
            namespace: 'dio',
            tools: <String>['cancel_in_flight'],
          ),
        ],
      );
      expect(out.keys, <String>['router']);
    });

    test('core tools are always included regardless of --extensions value', () {
      const List<ExtensionManifestEntry> handshake = <ExtensionManifestEntry>[
        ExtensionManifestEntry(namespace: 'core', tools: <String>[
          'tap', 'long_press', 'enter_text', 'scroll', 'scroll_until_visible',
          'gesture', 'system_back', 'wait', 'inspect_widget', 'done',
        ]),
        ExtensionManifestEntry(namespace: 'router', tools: <String>['navigate']),
      ];
      // Simulate the fixed CLI call: args.extensions = ['router'], union 'core'.
      final Map<String, List<ToolDescriptor>> out = buildExtensionTools(
        requested: <String>{'router', 'core'},
        handshake: handshake,
      );
      expect(out.containsKey('core'), isTrue,
          reason: 'core namespace must always be projected');
      expect(out['core'], hasLength(10));
      final List<String> coreNames =
          out['core']!.map((t) => t.name).toList();
      expect(coreNames, containsAll(<String>[
        'core.tap', 'core.enter_text', 'core.done',
        'core.scroll', 'core.scroll_until_visible', 'core.long_press',
        'core.gesture', 'core.system_back', 'core.wait', 'core.inspect_widget',
      ]));
    });

    test('core tools present even when --extensions is empty (empty requested union core)', () {
      const List<ExtensionManifestEntry> handshake = <ExtensionManifestEntry>[
        ExtensionManifestEntry(namespace: 'core', tools: <String>[
          'tap', 'long_press', 'enter_text', 'scroll', 'scroll_until_visible',
          'gesture', 'system_back', 'wait', 'inspect_widget', 'done',
        ]),
      ];
      final Map<String, List<ToolDescriptor>> out = buildExtensionTools(
        requested: <String>{'core'},   // args.extensions=[] union 'core'
        handshake: handshake,
      );
      expect(out.containsKey('core'), isTrue);
      expect(out['core'], hasLength(10));
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
