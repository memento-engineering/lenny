/// [ActionValidator] — validates a candidate action against the merged
/// tool list and the current observation.
///
/// PRD §10 step 7, §17. Stateless and web-compatible (no `dart:io`).
library;

import 'package:json_schema/json_schema.dart';

import '../observation/models.dart';
import '../provider/types.dart';
import 'result.dart';

/// Shape of the action handed to [ActionValidator.validate].
///
/// Decoupled from `ModelDecision` so non-provider callers (tests, ad-hoc
/// retries) can validate without constructing the full decision payload.
typedef ValidatorAction = ({String tool, Map<String, dynamic> args});

/// Core tools whose args reference one or more semantic node ids.
///
/// Mirrors the cx6.6 CoreExtension surface: tap / long-press / enter-text /
/// scroll / scroll-until-visible / inspect / gesture all take node ids.
/// `core.system_back`, `core.wait`, and `core.done` do not — they skip
/// the node pass.
const Set<String> _coreNodeTools = <String>{
  'core.tap',
  'core.long_press',
  'core.enter_text',
  'core.scroll',
  'core.scroll_until_visible',
  'core.inspect_widget',
  'core.gesture',
};

/// Per-tool list of arg keys that carry a semantic node id.
///
/// `core.scroll_until_visible` is the only tool with two node references
/// (the scrollable container and the target child). All others use a
/// single `node_id`.
const Map<String, List<String>> _nodeArgKeys = <String, List<String>>{
  'core.tap': <String>['node_id'],
  'core.long_press': <String>['node_id'],
  'core.enter_text': <String>['node_id'],
  'core.scroll': <String>['node_id'],
  'core.scroll_until_visible': <String>['scrollable_id', 'target_id'],
  'core.inspect_widget': <String>['node_id'],
  'core.gesture': <String>['node_id'],
};

/// Three-pass validator for candidate actions.
///
/// Passes, in order — first match wins:
///   1. **Tool exists** in the merged tool list. Rejects with
///      `unknown_tool` (carries `expected = [tool names]` and `got =
///      action.tool`).
///   2. **Args validate** against the tool's `inputSchema`
///      (draft-07). Rejects with `schema_invalid` (carries `pointer` and
///      `description` from the first reported error).
///   3. **Semantic-node check** for core tools that target node ids.
///      Looks up each id in `observation.core.nodes`. Rejects with
///      `node_not_found` if absent, `node_disabled` if `node.state`
///      contains the literal token `'disabled'`. Plugin-namespaced tools
///      (anything outside the `core.*` set in [_coreNodeTools]) skip
///      this pass.
///
/// Stateless and pure: same `(action, observation, tools)` always
/// produces structurally equal output.
class ActionValidator {
  const ActionValidator();

  /// Validate [action] against [tools] and the live UI in [observation].
  ValidationResult validate(
    ValidatorAction action,
    Observation observation,
    List<ToolDescriptor> tools,
  ) {
    // Pass 1: tool known?
    ToolDescriptor? tool;
    for (final t in tools) {
      if (t.name == action.tool) {
        tool = t;
        break;
      }
    }
    if (tool == null) {
      return ValidationReject(
        tool: action.tool,
        reason: 'unknown_tool',
        expected:
            tools.map((t) => t.name).toList(growable: false),
        got: action.tool,
        description:
            'tool "${action.tool}" is not available this turn',
      );
    }

    // Pass 2: args validate against inputSchema?
    final schema = JsonSchema.create(
      tool.inputSchema,
      schemaVersion: SchemaVersion.draft7,
    );
    final result = schema.validate(action.args);
    if (!result.isValid) {
      final err = result.errors.first;
      final pointer =
          err.instancePath.isEmpty ? '/' : err.instancePath;
      return ValidationReject(
        tool: action.tool,
        reason: 'schema_invalid',
        pointer: pointer,
        description: err.message,
      );
    }

    // Pass 3: core-tool semantic-node check.
    if (!_coreNodeTools.contains(action.tool)) {
      // Plugin tools and node-less core tools (system_back / wait /
      // done) only need passes 1+2.
      return const ValidationOk();
    }

    final argKeys = _nodeArgKeys[action.tool] ?? const <String>[];
    for (final argKey in argKeys) {
      final v = action.args[argKey];
      if (v is! int) {
        // Schema validation already enforced int-ness; defensive skip.
        continue;
      }
      final node = observation.core.nodes[v];
      if (node == null) {
        return ValidationReject(
          tool: action.tool,
          reason: 'node_not_found',
          pointer: '/$argKey',
          got: v,
          description:
              '$argKey=$v is not present in observation.core.nodes',
        );
      }
      if (node.state.contains('disabled')) {
        return ValidationReject(
          tool: action.tool,
          reason: 'node_disabled',
          pointer: '/$argKey',
          got: v,
          description:
              '$argKey=$v is disabled (state: ${node.state})',
        );
      }
    }
    return const ValidationOk();
  }
}
