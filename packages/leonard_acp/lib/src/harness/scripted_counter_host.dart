/// A deterministic [LoopHost] modelling a counter screen.
///
/// Exists so the ACP provider can be measured against a REAL `LoopDriver`
/// session — full observation payloads, a `oneOf` schema over the merged tool
/// list, and the three-pass [ActionValidator] — without a device, a Flutter
/// binding, or a VM service in the loop.
///
/// It is a genuine test of whether the agent reads the observation: `core.tap`
/// carries a `node_id`, and the validator rejects any id that is not present
/// in `observation.core.nodes`. An agent that hallucinates a node id fails
/// validation exactly as it would against a live app.
library;

import 'package:leonard_agent/leonard_agent.dart';

/// Semantic node id of the increment button.
const int kIncrementNodeId = 11;

/// Semantic node id of the counter label.
const int kCounterNodeId = 12;

/// A scripted counter app: tap the button, the number goes up.
class ScriptedCounterHost implements LoopHost {
  ScriptedCounterHost({this.target = 3});

  /// Counter value the goal asks the agent to reach.
  final int target;

  int _counter = 0;

  /// Current counter value — the harness asserts on this to decide whether
  /// the run actually succeeded rather than merely terminated.
  int get counter => _counter;

  @override
  String get goal =>
      'Tap the Increment button until the counter reads $target, then call '
      'core.done. Do not call core.done before the counter reads $target.';

  @override
  String get agentsMd => kDefaultAgentsMd;

  @override
  Future<Observation> observe() async => Observation(
    core: CoreFragment(
      routeStack: const <String>['/'],
      nodes: <int, SemanticsNode>{
        kCounterNodeId: SemanticsNode(
          id: kCounterNodeId,
          role: 'text',
          label: 'Count: $_counter',
          identifier: 'counter_label',
          state: const <String>[],
          actions: const <String>[],
          rect: const <int>[0, 100, 200, 140],
        ),
        kIncrementNodeId: const SemanticsNode(
          id: kIncrementNodeId,
          role: 'button',
          label: 'Increment',
          identifier: 'increment_button',
          state: <String>[],
          actions: <String>['tap'],
          rect: <int>[0, 200, 200, 260],
        ),
      },
      errors: const <RuntimeError>[],
    ),
    extensions: const <String, ExtensionFragment>{},
    stability: const StabilityMetadata(
      policy: 'scripted',
      terminatedBy: 'immediate',
      durationMs: 0,
      frameworkBusy: <String, dynamic>{},
      extensionsBusy: <ExtensionBusy>[],
    ),
  );

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    switch (tool) {
      case 'core.tap':
        if (args['node_id'] == kIncrementNodeId) _counter++;
        return <String, dynamic>{'ok': true, 'counter': _counter};
      case 'core.done':
        return <String, dynamic>{'ok': true};
      default:
        return <String, dynamic>{'ok': false, 'error': 'unknown tool: $tool'};
    }
  }

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}

  @override
  void disableExtension(String namespace, String reason) {}

  @override
  Set<String> activeExtensionNamespaces() => const <String>{'core'};

  @override
  List<ToolDescriptor> mergedTools() => const <ToolDescriptor>[
    ToolDescriptor(
      name: 'core.tap',
      description: 'Tap the semantic node with the given id.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'required': <String>['node_id'],
        'properties': <String, dynamic>{
          'node_id': <String, dynamic>{
            'type': 'integer',
            'description': 'id of a node present in the current observation',
          },
        },
        'additionalProperties': false,
      },
    ),
    ToolDescriptor(
      name: 'core.done',
      description:
          'Declare the goal complete. Only call this once the goal is '
          'actually satisfied by the current observation.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'required': <String>['reason'],
        'properties': <String, dynamic>{
          'reason': <String, dynamic>{'type': 'string'},
        },
        'additionalProperties': false,
      },
    ),
  ];
}
