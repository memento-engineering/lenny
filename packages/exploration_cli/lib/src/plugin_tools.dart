/// Build the `pluginTools` map handed to [DefaultLoopHost.fromSession]
/// from the user's `--plugins` whitelist and the binding's handshake
/// manifest.
///
/// The handshake (`ext.flutter.exploration.handshake`,
/// [PluginManifestEntry]) only carries pre-namespaced tool *names*; full
/// JSON-schema input descriptors live in `package:exploration_flutter`
/// inside the running app and are not currently fetched over the wire.
/// Until cx6.39 plumbs full schemas through the contract, the CLI emits
/// `ToolDescriptor`s with a permissive object input schema so the model
/// at least *sees* the plugin tools and can call them; the binding-side
/// `ActionValidator` (cx6.17) is the authoritative schema check on
/// every action.
///
/// Selection rules:
///
///   * Empty `requested` → empty map (no plugin tools).
///   * `requested` namespaces that are absent from the handshake are
///     silently dropped (the binding has no such plugin loaded). The
///     caller may log unknown namespaces using [unknownPluginNamespaces].
///   * `requested` namespaces that *are* in the handshake produce a
///     `ToolDescriptor` per tool name reported by that handshake entry.
///
/// Pure (no `dart:io`), so it's covered by `dart test` without a fake
/// VM service.
library;

import 'package:exploration_agent/exploration_agent.dart';

/// Build the `pluginTools` map from a user-supplied namespace whitelist
/// and the binding's handshake manifest. See library doc for semantics.
Map<String, List<ToolDescriptor>> buildPluginTools({
  required List<String> requested,
  required List<PluginManifestEntry> handshake,
}) {
  if (requested.isEmpty) return const <String, List<ToolDescriptor>>{};
  final Set<String> wanted = requested.toSet();
  final Map<String, List<ToolDescriptor>> out =
      <String, List<ToolDescriptor>>{};
  for (final PluginManifestEntry p in handshake) {
    if (!wanted.contains(p.namespace)) continue;
    out[p.namespace] = <ToolDescriptor>[
      for (final String name in p.tools)
        ToolDescriptor(
          name: name,
          description:
              'Plugin tool $name (schema sourced from binding at runtime; '
              'CLI emits a permissive descriptor pending cx6.39).',
          inputSchema: const <String, dynamic>{
            'type': 'object',
            'additionalProperties': true,
          },
        ),
    ];
  }
  return out;
}

/// Names the user listed on `--plugins` that are *not* present in the
/// handshake manifest (i.e. the binding does not have a plugin with
/// that namespace loaded). Returned in the order they appeared on the
/// command line so warnings match user input.
List<String> unknownPluginNamespaces({
  required List<String> requested,
  required List<PluginManifestEntry> handshake,
}) {
  final Set<String> active = <String>{
    for (final PluginManifestEntry p in handshake) p.namespace,
  };
  return <String>[
    for (final String ns in requested)
      if (!active.contains(ns)) ns,
  ];
}
