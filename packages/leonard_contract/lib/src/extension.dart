// The class-level dartdoc on [LeonardExtension] intentionally embeds
// `List<LeonardResource>` / `List<LeonardPrompt>` verbatim because
// downstream tooling greps for that exact phrase to verify the v2
// extensibility contract (PRD §8).
// ignore_for_file: unintended_html_in_doc_comment

import 'dart:async';

import 'extension_context.dart';
import 'types.dart';

/// A single tool exposed by an [LeonardExtension].
///
/// The [name] is a bare token (no `.`); the host registry prefixes it with
/// the extension's namespace, producing the fully-qualified name
/// `<namespace>.<name>` exposed to the agent.
abstract class LeonardTool {
  const LeonardTool();

  /// Bare token (`^[a-z][a-z0-9_]*$` recommended). Must not contain `.`.
  String get name;

  /// Human-readable description surfaced to the agent.
  String get description;

  /// JSON Schema fragment for this tool's input.
  JsonSchema get inputSchema;

  /// Invoke the tool with [args].
  Future<ToolResult> call(Map<String, Object?> args);
}

/// EXPERIMENTAL — v1 extension contract (PRD §7).
///
/// A extension contributes tools and busy-state signals to a Flutter
/// Exploration session. Extensions that also observe app state mix in
/// [PerceptionExtension] and contribute their observation via the perception
/// path (`buildPerception()`); the binding serializes that into the
/// `extensions.<namespace>` fragment. Implementations are registered with the
/// host binding and dispatched by the [ExtensionRegistry] in registration
/// order.
///
/// Versioning (PRD §7.7): adding tools, fragment fields, or busy
/// heuristics is NOT breaking. Unknown fragment fields are passed
/// through opaquely.
///
/// v2 extension (PRD §8): List<LeonardResource> get resources and
/// List<LeonardPrompt> get prompts may be added with default empty
/// implementations without breaking existing extensions.
abstract class LeonardExtension {
  const LeonardExtension();

  /// Extension namespace; must match `^[a-z][a-z0-9_]*$`.
  ///
  /// Used to prefix tool names (`<namespace>.<tool>`) and to scope VM
  /// service extensions (`ext.exploration.<namespace>.<suffix>`).
  String get namespace;

  /// Tools this extension contributes. Returned in stable order.
  List<LeonardTool> get tools;

  /// Called once per session, in registration order. May register error
  /// handlers, VM extensions, and frame callbacks via [ctx].
  Future<void> initialize(ExtensionContext ctx);

  /// Report whether the extension considers the app busy.
  Future<BusyState> busyState();

  /// Notify the extension that an action just executed.
  Future<void> onActionExecuted(ExecutedAction action);

  /// Tear down resources. Called once at session end. Exception-isolated
  /// by the registry; every extension's `dispose` runs even if earlier
  /// extensions throw.
  Future<void> dispose();
}
