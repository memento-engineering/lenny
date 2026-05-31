/// Tests for the `--plugins`-to-`pluginTools` projection that the CLI
/// hands to [DefaultLoopHost.fromSession]. Pure-Dart, no `dart:io`.
library;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_cli/src/plugin_tools.dart';
import 'package:test/test.dart';

void main() {
  group('buildPluginTools', () {
    test('empty --plugins → empty map', () {
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
      // Permissive object schema so the model can call the tool;
      // binding-side ActionValidator (cx6.17) is the authoritative check.
      expect(out['router']!.single.inputSchema['type'], 'object');
    });

    test('non-empty --plugins yields non-empty pluginTools reaching host '
        '(regression: the prior build wired const {} through)', () {
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
          reason: 'a non-empty --plugins must produce a non-empty map');
      expect(out['router'], hasLength(2));
      expect(
        out['router']!.map((t) => t.name).toList(),
        <String>['router.go', 'router.back'],
      );
    });

    test('handshake namespace not in --plugins is excluded', () {
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

    test('core tools are always included regardless of --plugins value', () {
      const List<PluginManifestEntry> handshake = <PluginManifestEntry>[
        PluginManifestEntry(namespace: 'core', tools: <String>[
          'tap', 'long_press', 'enter_text', 'scroll', 'scroll_until_visible',
          'gesture', 'system_back', 'wait', 'inspect_widget', 'done',
        ]),
        PluginManifestEntry(namespace: 'router', tools: <String>['navigate']),
      ];
      // Simulate the fixed CLI call: args.plugins = ['router'], union 'core'.
      final Map<String, List<ToolDescriptor>> out = buildPluginTools(
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

    test('core tools present even when --plugins is empty (empty requested union core)', () {
      const List<PluginManifestEntry> handshake = <PluginManifestEntry>[
        PluginManifestEntry(namespace: 'core', tools: <String>[
          'tap', 'long_press', 'enter_text', 'scroll', 'scroll_until_visible',
          'gesture', 'system_back', 'wait', 'inspect_widget', 'done',
        ]),
      ];
      final Map<String, List<ToolDescriptor>> out = buildPluginTools(
        requested: <String>{'core'},   // args.plugins=[] union 'core'
        handshake: handshake,
      );
      expect(out.containsKey('core'), isTrue);
      expect(out['core'], hasLength(10));
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
