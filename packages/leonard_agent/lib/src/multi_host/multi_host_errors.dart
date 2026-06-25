/// Error types for the multi-host harness (m3, `lenny-qxx.3`).
///
/// Pure, io-free. Both carry the offending namespace plus enough context
/// for an actionable `toString`, surfaced once at attach (`start`) or
/// synchronously at dispatch (never mid-wire-call).
library;

/// Thrown by `MultiHostSession.start` when two attached hosts each report
/// the SAME manifest namespace in their handshake.
///
/// This is a configuration error (two hosts both claiming, e.g., `core`):
/// `<namespace>.<tool>` would be ambiguous. By design it never happens —
/// `core`/`router`/`riverpod`/`dio` are Flutter-host-only and `native` is
/// native-host-only — but the merge fails fast rather than silently
/// shadowing one host with the other.
class MultiHostNamespaceCollision implements Exception {
  MultiHostNamespaceCollision(this.namespace, List<String> labels)
    : labels = List<String>.unmodifiable(labels);

  /// The namespace claimed by more than one host.
  final String namespace;

  /// The diagnostic labels of the hosts that collided on [namespace].
  final List<String> labels;

  @override
  String toString() =>
      'MultiHostNamespaceCollision: namespace "$namespace" is claimed by '
      'more than one attached host (${labels.join(', ')}). Each namespace '
      'must be owned by exactly one host.';
}

/// Thrown synchronously by `MultiHostSession.executeAction` (before any
/// wire call) when an action's namespace is owned by no attached host.
///
/// Catches a model hallucinating a namespace or attaching to fewer hosts
/// than the manifest implies — fail fast so the loop never hangs on an
/// unroutable name.
class MultiHostUnknownNamespace implements Exception {
  MultiHostUnknownNamespace(this.namespace, List<String> known)
    : known = List<String>.unmodifiable(known);

  /// The unmapped namespace from the action name.
  final String namespace;

  /// The namespaces that ARE routable (sorted for a stable message).
  final List<String> known;

  @override
  String toString() =>
      'MultiHostUnknownNamespace: namespace "$namespace" is not owned by any '
      'attached host. Known namespaces: ${known.join(', ')}.';
}
