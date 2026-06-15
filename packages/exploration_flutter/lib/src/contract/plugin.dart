// The class-level dartdoc on [ExplorationPlugin] intentionally embeds
// `List<ExplorationResource>` / `List<ExplorationPrompt>` verbatim because
// downstream tooling greps for that exact phrase to verify the v2
// extensibility contract (PRD §8).
// ignore_for_file: unintended_html_in_doc_comment

import 'dart:async';

import 'plugin_context.dart';
import 'types.dart';

/// A single tool exposed by an [ExplorationPlugin].
///
/// The [name] is a bare token (no `.`); the host registry prefixes it with
/// the plugin's namespace, producing the fully-qualified name
/// `<namespace>.<name>` exposed to the agent.
abstract class ExplorationTool {
  const ExplorationTool();

  /// Bare token (`^[a-z][a-z0-9_]*$` recommended). Must not contain `.`.
  String get name;

  /// Human-readable description surfaced to the agent.
  String get description;

  /// JSON Schema fragment for this tool's input.
  JsonSchema get inputSchema;

  /// Invoke the tool with [args].
  Future<ToolResult> call(Map<String, Object?> args);
}

/// EXPERIMENTAL — v1 plugin contract (PRD §7).
///
/// A plugin contributes tools and busy-state signals to a Flutter
/// Exploration session. Plugins that also observe app state mix in
/// [PerceptionPlugin] and contribute their observation via the perception
/// path (`buildPerception()`); the binding serializes that into the
/// `plugins.<namespace>` fragment. Implementations are registered with the
/// host binding and dispatched by the [PluginRegistry] in registration
/// order.
///
/// Versioning (PRD §7.7): adding tools, fragment fields, or busy
/// heuristics is NOT breaking. Unknown fragment fields are passed
/// through opaquely.
///
/// v2 extension (PRD §8): List<ExplorationResource> get resources and
/// List<ExplorationPrompt> get prompts may be added with default empty
/// implementations without breaking existing plugins.
abstract class ExplorationPlugin {
  const ExplorationPlugin();

  /// Plugin namespace; must match `^[a-z][a-z0-9_]*$`.
  ///
  /// Used to prefix tool names (`<namespace>.<tool>`) and to scope VM
  /// service extensions (`ext.exploration.<namespace>.<suffix>`).
  String get namespace;

  /// Tools this plugin contributes. Returned in stable order.
  List<ExplorationTool> get tools;

  /// Called once per session, in registration order. May register error
  /// handlers, VM extensions, and frame callbacks via [ctx].
  Future<void> initialize(PluginContext ctx);

  /// Report whether the plugin considers the app busy.
  Future<BusyState> busyState();

  /// Notify the plugin that an action just executed.
  Future<void> onActionExecuted(ExecutedAction action);

  /// Tear down resources. Called once at session end. Exception-isolated
  /// by the registry; every plugin's `dispose` runs even if earlier
  /// plugins throw.
  Future<void> dispose();
}
