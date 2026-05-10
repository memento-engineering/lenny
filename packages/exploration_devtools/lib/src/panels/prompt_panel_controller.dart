import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';

import 'panel_provider_factory.dart';
import 'prompt_panel_config.dart';
import 'provider_config.dart';

/// Builds an [ExplorationSession] connected to [vmServiceUri]. Tests
/// override this with a fake; production wires the real
/// [ExplorationSession.connect] static.
typedef SessionFactory = Future<ExplorationSession> Function(Uri vmServiceUri);

/// Drives the in-panel session lifecycle for [PromptPanel].
///
/// Owns:
///   - the [ExplorationSession] handshake / lifecycle,
///   - the [PanelProviderFactory] (test seam — production uses
///     [buildPanelProvider]), and
///   - the [ModelProvider] constructed for the active turn-set, so
///     tests can assert on the wire shape (Bearer auth, conversation
///     id, etc).
class PromptPanelController {
  PromptPanelController({
    required this.vmServiceUri,
    SessionFactory? factory,
    PanelProviderFactory? providerFactory,
  })  : _factory = factory ?? ExplorationSession.connect,
        _providerFactory = providerFactory ?? buildPanelProvider;

  final Uri vmServiceUri;
  final SessionFactory _factory;
  final PanelProviderFactory _providerFactory;
  final StreamController<SessionProgressEvent> _events =
      StreamController<SessionProgressEvent>.broadcast();

  ExplorationSession? _session;
  StreamSubscription<SessionProgressEvent>? _sub;
  ModelProvider? _provider;

  /// `true` between [start] and [stop].
  bool get running => _session != null;

  /// Provider constructed for the active session (visible for tests
  /// + future `session.run` wiring).
  ModelProvider? get activeProvider => _provider;

  /// Forwards every [SessionProgressEvent] from the active session.
  Stream<SessionProgressEvent> get events => _events.stream;

  /// Connect, subscribe, build the [ModelProvider] from [providerCfg]
  /// + [panelCfg.modelId], and start a session for [panelCfg].
  ///
  /// Note: the panel does not (yet) drive `session.run` directly —
  /// the host tool-list / `DefaultLoopHost.fromSession` wiring is a
  /// follow-up bead. For now the controller exposes [activeProvider]
  /// so the next step in the pipeline can attach to it.
  ///
  /// Throws [StateError] if a session is already running.
  Future<void> start(
    PromptPanelConfig panelCfg, {
    ProviderConfig? providerCfg,
  }) async {
    if (_session != null) {
      throw StateError('session already running');
    }
    final session = await _factory(vmServiceUri);
    _session = session;
    _sub = session.progress.listen(_events.add);
    await session.start(panelCfg.goal, panelCfg.toExplorationConfig());

    if (providerCfg != null) {
      // Derive a stable session id from the goal hash + clock so two
      // concurrent panels don't collide on the same conversation id.
      final sessionId =
          'panel-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      _provider = _providerFactory(providerCfg, panelCfg.modelId, sessionId);
    }
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
    _provider = null;
  }

  /// Stop and close the broadcast stream. After [dispose] the controller
  /// is unusable.
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
