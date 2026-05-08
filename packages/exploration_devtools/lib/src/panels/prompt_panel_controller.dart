import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';

import 'prompt_panel_config.dart';

/// Builds an [ExplorationSession] connected to [vmServiceUri]. Tests
/// override this with a fake; production wires the real
/// [ExplorationSession.connect] static.
typedef SessionFactory = Future<ExplorationSession> Function(Uri vmServiceUri);

/// Drives the in-panel session lifecycle for [PromptPanel]. cx6.31 will
/// extend this with `injectHint` / `interrupt` without restructuring the
/// widget contract.
class PromptPanelController {
  PromptPanelController({
    required this.vmServiceUri,
    SessionFactory? factory,
  }) : _factory = factory ?? ExplorationSession.connect;

  final Uri vmServiceUri;
  final SessionFactory _factory;
  final StreamController<SessionProgressEvent> _events =
      StreamController<SessionProgressEvent>.broadcast();

  ExplorationSession? _session;
  StreamSubscription<SessionProgressEvent>? _sub;

  /// `true` between [start] and [stop].
  bool get running => _session != null;

  /// Forwards every [SessionProgressEvent] from the active session.
  Stream<SessionProgressEvent> get events => _events.stream;

  /// Connect, subscribe, and start a session for [cfg]. Throws
  /// [StateError] if a session is already running.
  Future<void> start(PromptPanelConfig cfg) async {
    if (_session != null) {
      throw StateError('session already running');
    }
    final session = await _factory(vmServiceUri);
    _session = session;
    _sub = session.progress.listen(_events.add);
    await session.start(cfg.goal, cfg.toExplorationConfig());
  }

  /// End the active session and tear down the subscription. No-op if
  /// nothing is running.
  Future<void> stop() async {
    final session = _session;
    if (session == null) return;
    await session.end();
    await _sub?.cancel();
    _sub = null;
    _session = null;
  }

  /// Stop and close the broadcast stream. After [dispose] the controller
  /// is unusable.
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
