/// The Leonard *contract* extension for a tmux client.
///
/// A stateful, self-watching extension — the same shape as the Flutter
/// reference extensions (riverpod/dio): [initialize] subscribes to a
/// genesis_tmux [ObservationSource] and keeps a live [TmuxObservation]
/// current off the [TmuxEvent] stream, so [buildPerception] reads it
/// **synchronously**. There is no async work at observation time; the async
/// I/O lives in the watcher (started in [initialize]) exactly as riverpod's
/// observer accrues changes out-of-band. Tools (`send_keys`, `new_session`)
/// dispatch to the underlying genesis_tmux verbs and refresh the snapshot so
/// the next observation reflects the action promptly.
library;

import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_contract/leonard_contract.dart';

import 'tmux_observation.dart';
import 'tmux_perception.dart';

/// Wires a [TmuxClient] into Leonard as the `tmux` extension.
class TmuxExtension extends LeonardExtension with PerceptionExtension {
  /// Observes and drives [client]. Each refresh captures the last
  /// [captureLines] of every pane; [pollInterval] is the watcher's poll tick.
  TmuxExtension(
    this.client, {
    this.captureLines = 40,
    Duration pollInterval = const Duration(seconds: 1),
  }) : _pollInterval = pollInterval;

  /// The tmux client this extension observes and drives.
  final TmuxClient client;

  /// How many lines of each pane's tail to include in an observation.
  final int captureLines;

  final Duration _pollInterval;

  ObservationSource? _source;
  StreamSubscription<TmuxEvent>? _sub;
  TmuxObservation? _live;
  bool _refreshing = false;
  bool _disposed = false;

  @override
  String get namespace => 'tmux';

  @override
  List<LeonardTool> get tools => <LeonardTool>[
    _SendKeysTool(this),
    _NewSessionTool(this),
  ];

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    final source = PollObservationSource(
      client: client,
      captureLines: captureLines,
      interval: _pollInterval,
    );
    _source = source;
    await source.start();
    _sub = source.events.listen((_) => _scheduleRefresh());
    await _refresh();
  }

  /// Pre-build seam: a no-op. The watcher keeps [_live] current out-of-band,
  /// so observation is a pure synchronous read.
  @override
  void prepareForObservation() {}

  @override
  bool isPerceptionIdle() => _live == null;

  @override
  Seed buildPerception() => TmuxPerception(_live!);

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await _source?.close();
    _source = null;
  }

  /// Re-gathers the live snapshot now. Called by the tools after they act so
  /// the next observation reflects the change without waiting for the tick.
  Future<void> refreshNow() => _refresh();

  void _scheduleRefresh() {
    if (_disposed || _refreshing) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      _live = await gatherTmuxObservation(client, captureLines: captureLines);
    } on Object {
      // Keep the last good snapshot on a transient gather failure.
    } finally {
      _refreshing = false;
    }
  }
}

class _SendKeysTool extends LeonardTool {
  _SendKeysTool(this._ext);

  final TmuxExtension _ext;

  @override
  String get name => 'send_keys';

  @override
  String get description =>
      'Send literal text to a tmux pane, then Enter (unless enter=false). '
      'Address the pane by its id (e.g. "%0").';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'pane': <String, Object?>{
        'type': 'string',
        'description': 'tmux pane id, e.g. %0',
      },
      'text': <String, Object?>{'type': 'string'},
      'enter': <String, Object?>{'type': 'boolean'},
    },
    'required': <String>['pane', 'text'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final pane = args['pane'];
    final text = args['text'];
    if (pane is! String || text is! String) {
      return const ToolResult(
        ok: false,
        error: 'pane and text are required strings',
      );
    }
    try {
      await _ext.client.sendKeys(
        pane,
        text,
        enter: args['enter'] as bool? ?? true,
      );
    } on TmuxException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
    await _ext.refreshNow();
    return ToolResult(ok: true, value: <String, Object?>{'pane': pane});
  }
}

class _NewSessionTool extends LeonardTool {
  _NewSessionTool(this._ext);

  final TmuxExtension _ext;

  @override
  String get name => 'new_session';

  @override
  String get description =>
      'Create a detached tmux session and return its first pane id.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'name': <String, Object?>{'type': 'string'},
      'workdir': <String, Object?>{'type': 'string'},
    },
    'required': <String>['name'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final name = args['name'];
    if (name is! String) {
      return const ToolResult(ok: false, error: 'name is required');
    }
    try {
      final paneId = await _ext.client.newSession(
        name: name,
        workdir: args['workdir'] as String?,
      );
      await _ext.refreshNow();
      return ToolResult(ok: true, value: <String, Object?>{'pane': paneId});
    } on TmuxException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
  }
}
