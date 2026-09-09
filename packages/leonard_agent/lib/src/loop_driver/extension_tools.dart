/// Build the `extensionTools` map handed to [DefaultLoopHost.fromSession]
/// from a caller-supplied namespace whitelist and the binding's
/// handshake manifest.
///
/// The handshake (`ext.leonard.core.handshake`,
/// [ExtensionManifestEntry]) carries authoritative *bare* tool names grouped
/// under each extension namespace and may carry the device-owned description
/// and JSON schema for each name. This helper prefixes names into the
/// fully-qualified `<namespace>.<tool>` [ToolDescriptor.name] that
/// `LoopHost.executeAction` requires and preserves schema-bearing descriptors
/// unchanged. A permissive object schema is emitted only for a tool from a
/// legacy names-only handshake.
///
/// Selection rules:
///
///   * Empty `requested` → empty map (no extension tools).
///   * `requested` namespaces that are absent from the handshake are
///     silently dropped (the binding has no such extension loaded). The
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

/// Project one handshake entry into qualified model tool descriptors.
///
/// [ExtensionManifestEntry.tools] is authoritative for membership and order.
/// A matching schema-bearing handshake descriptor is reused unchanged; a
/// legacy name without one receives the permissive compatibility descriptor.
List<ToolDescriptor> manifestToolDescriptors(ExtensionManifestEntry entry) {
  final Map<String, ToolDescriptor> descriptorsByName =
      <String, ToolDescriptor>{
        for (final ToolDescriptor descriptor in entry.toolDescriptors)
          descriptor.name: descriptor,
      };
  return <ToolDescriptor>[
    for (final String name in entry.tools)
      descriptorsByName['${entry.namespace}.$name'] ??
          ToolDescriptor(
            name: '${entry.namespace}.$name',
            description:
                'Extension tool ${entry.namespace}.$name '
                '(permissive schema).',
            inputSchema: const <String, dynamic>{
              'type': 'object',
              'additionalProperties': true,
            },
          ),
  ];
}

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
    out[p.namespace] = manifestToolDescriptors(p);
  }
  return out;
}

/// Names the caller listed in `requested` that are *not* present in
/// the handshake manifest (i.e. the binding does not have an extension
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
