/// The Leonard extension surface for a tmux client.
///
/// Two halves, both in Leonard's pure-Dart vocabulary (`leonard_agent`): an
/// [observe] that produces an `ExtensionFragment` under the `tmux` namespace
/// (gather → project → serialize), and a set of [tools] (`ToolDescriptor`s)
/// dispatched by [executeAction] to the underlying genesis_tmux verbs. A future
/// `TmuxLoopHost implements LoopHost` can drive the agent loop with these.
library;

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_agent/leonard_agent.dart';

import 'tmux_observation.dart';
import 'tmux_perception.dart';

/// Wires a [TmuxClient] into Leonard as the `tmux` extension.
class TmuxExtension {
  /// Observes and drives [client]; each [observe] captures the last
  /// [captureLines] of every pane.
  TmuxExtension(this.client, {this.captureLines = 40});

  /// The tmux client this extension observes and drives.
  final TmuxClient client;

  /// How many lines of each pane's tail to include in an observation.
  final int captureLines;

  /// Leonard namespace for this extension's tools and observation fragment.
  String get namespace => 'tmux';

  /// The tools this extension contributes to the agent (already namespaced).
  List<ToolDescriptor> get tools => [
    ToolDescriptor(
      name: '$namespace.send_keys',
      description:
          'Send literal text to a tmux pane, then Enter (unless enter=false). '
          'Address the pane by its id (e.g. "%0").',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'pane': {'type': 'string', 'description': 'tmux pane id, e.g. %0'},
          'text': {'type': 'string'},
          'enter': {'type': 'boolean'},
        },
        'required': ['pane', 'text'],
        'additionalProperties': false,
      },
    ),
    ToolDescriptor(
      name: '$namespace.new_session',
      description:
          'Create a detached tmux session and return its first pane id.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'workdir': {'type': 'string'},
        },
        'required': ['name'],
        'additionalProperties': false,
      },
    ),
  ];

  /// Gathers the current tmux state and projects it into a `tmux`
  /// [ExtensionFragment] (the JSON map Leonard's observation pipeline consumes).
  Future<ExtensionFragment> observe() async {
    final observation = await gatherTmuxObservation(
      client,
      captureLines: captureLines,
    );
    final owner = PerceptionOwner();
    final root = owner.mountRoot(TmuxPerception(observation));
    final data = serializePerceptionFragment(root);
    owner.unmountRoot();
    return ExtensionFragment(
      namespace: namespace,
      data: Map<String, dynamic>.from(data),
      deltaFriendly: true,
    );
  }

  /// Dispatches a namespaced [tool] call to the matching genesis_tmux verb.
  /// Returns a JSON-able result map (`{ok: true, …}` or `{ok: false, error}`),
  /// mirroring Leonard's tool-result convention.
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (tool) {
        case 'tmux.send_keys':
          final pane = args['pane'];
          final text = args['text'];
          if (pane is! String || text is! String) {
            return _err('pane and text are required strings');
          }
          await client.sendKeys(
            pane,
            text,
            enter: args['enter'] as bool? ?? true,
          );
          return {'ok': true, 'pane': pane};
        case 'tmux.new_session':
          final name = args['name'];
          if (name is! String) return _err('name is required');
          final paneId = await client.newSession(
            name: name,
            workdir: args['workdir'] as String?,
          );
          return {'ok': true, 'pane': paneId};
        default:
          return _err('unknown tool "$tool"');
      }
    } on TmuxException catch (e) {
      return _err(e.message);
    }
  }

  Map<String, dynamic> _err(String message) => {'ok': false, 'error': message};
}
