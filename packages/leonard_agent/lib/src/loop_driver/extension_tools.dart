/// Build the `extensionTools` map handed to [DefaultLoopHost.fromSession]
/// from a caller-supplied namespace whitelist and the binding's
/// handshake manifest.
///
/// The handshake (`ext.exploration.core.handshake`,
/// [ExtensionManifestEntry]) carries *bare* tool names grouped under each
/// plugin namespace; this helper prefixes the namespace to produce the
/// fully-qualified `<namespace>.<tool>` [ToolDescriptor.name] that
/// `LoopHost.executeAction` requires. Full JSON-schema input
/// descriptors live in `package:leonard_flutter` inside the running
/// app and are not currently fetched over the wire. Until full schemas
/// are plumbed through the contract, this helper emits [ToolDescriptor]s
/// with a permissive object input schema so the model at least *sees*
/// the extension tools and can call them; the binding-side `ActionValidator`
/// is the authoritative schema check on every action.
///
/// Selection rules:
///
///   * Empty `requested` → empty map (no plugin tools).
///   * `requested` namespaces that are absent from the handshake are
///     silently dropped (the binding has no such plugin loaded). The
///     caller may log unknown namespaces using [unknownExtensionNamespaces].
///   * `requested` namespaces that *are* in the handshake produce a
///     [ToolDescriptor] per tool name reported by that handshake entry.
///
/// Pure (no `dart:io`), so this lives in `leonard_agent` and is
/// shared by both the CLI (`leonard_cli`) and the DevTools panel
/// (`leonard_devtools`) — both frontends drive
/// `DefaultLoopHost.fromSession(...)` and must agree on the projection.
library;

import '../provider/types.dart';
import '../types.dart';

/// Build the `extensionTools` map from a caller-supplied namespace
/// whitelist and the binding's handshake manifest. See library doc for
/// semantics.
Map<String, List<ToolDescriptor>> buildExtensionTools({
  required Iterable<String> requested,
  required List<ExtensionManifestEntry> handshake,
}) {
  if (requested.isEmpty) return const <String, List<ToolDescriptor>>{};
  final Set<String> wanted = requested.toSet();
  final Map<String, List<ToolDescriptor>> out =
      <String, List<ToolDescriptor>>{};
  for (final ExtensionManifestEntry p in handshake) {
    if (!wanted.contains(p.namespace)) continue;
    out[p.namespace] = <ToolDescriptor>[
      for (final String name in p.tools)
        ToolDescriptor(
          name: '${p.namespace}.$name',
          description:
              'Extension tool ${p.namespace}.$name '
              '(permissive schema).',
          inputSchema: const <String, dynamic>{
            'type': 'object',
            'additionalProperties': true,
          },
        ),
    ];
  }
  return out;
}

/// Names the caller listed in `requested` that are *not* present in
/// the handshake manifest (i.e. the binding does not have a plugin
/// with that namespace loaded). Returned in iteration order of
/// [requested] so warnings match caller input.
List<String> unknownExtensionNamespaces({
  required Iterable<String> requested,
  required List<ExtensionManifestEntry> handshake,
}) {
  final Set<String> active = <String>{
    for (final ExtensionManifestEntry p in handshake) p.namespace,
  };
  return <String>[
    for (final String ns in requested)
      if (!active.contains(ns)) ns,
  ];
}
