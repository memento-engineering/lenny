/// Collaborator interface that [LoopDriver] uses to talk to the
/// `LeonardSession` (and its underlying `VmServiceClient`).
///
/// Encapsulates the slice of session/client surface the driver needs
/// — observation, action execution, plugin-notification, plugin
/// disable, dynamic tool list. Tests inject a fake; production wires
/// up `LeonardSession.toLoopHost()`.
library;

import '../observation/models.dart';
import '../provider/types.dart';

abstract class LoopHost {
  /// PRD §10 steps 1+2+3 — stabilize and deserialize the typed
  /// observation. Must throw [VmServiceConnectionLost] when the
  /// underlying transport is gone, so the driver can terminate the
  /// session with `harnessError = connection_lost`.
  Future<Observation> observe();

  /// PRD §10 step 8 — execute the validated action. Returns the
  /// extension's response payload. Must throw
  /// [VmServiceConnectionLost] on transport failure.
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  );

  /// PRD §10 step 9 — fan out the executed action to plugins.
  /// Implementations may no-op when there are no active plugins.
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  );

  /// PRD §17 auto-disable. Implementations record the disable reason
  /// and exclude [namespace] from subsequent [mergedTools] /
  /// [activeExtensionNamespaces] results.
  void disableExtension(String namespace, String reason);

  /// PRD §16.2 — merged tool list (host core + active plugin tools)
  /// regenerated each turn. Auto-disabled plugins must already be
  /// excluded.
  List<ToolDescriptor> mergedTools();

  /// Active plugin namespaces this turn. Auto-disabled plugins must
  /// already be excluded.
  Set<String> activeExtensionNamespaces();

  /// AGENTS.md content for prompt assembly. Constant per session.
  String get agentsMd;

  /// Run goal supplied at session start.
  String get goal;
}
