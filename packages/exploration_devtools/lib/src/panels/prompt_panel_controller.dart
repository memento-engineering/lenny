import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';

import '../broadcast_trajectory_sink.dart';
import 'panel_provider_factory.dart';
import 'prompt_panel_config.dart';
import 'provider_config.dart';

/// Builds an [ExplorationSession]. The closure owns whatever connection
/// it needs — production wires a closure over `serviceManager.service` +
/// the main isolate id (via [ExplorationSession.fromVmService]); tests
/// inject a fake.
typedef SessionFactory = Future<ExplorationSession> Function();

/// Drives the in-panel session lifecycle for [PromptPanel].
///
/// Owns:
///   - the [ExplorationSession] handshake / lifecycle,
///   - the [PanelProviderFactory] (test seam — production uses
///     [buildPanelProvider]),
///   - the [ModelProvider] constructed for the active turn-set, so
///     tests can assert on the wire shape (Bearer auth, conversation
///     id, etc), and
///   - the [TrajectoryWriter] backed by a [BroadcastTrajectorySink]
///     that the timeline tab observes through [trajectory]. The
///     disk-backed [DtdTrajectorySink] in this package is the future
///     production successor for persistence.
class PromptPanelController {
  PromptPanelController({
    required SessionFactory factory,
    PanelProviderFactory? providerFactory,
  })  : _factory = factory,
        _providerFactory = providerFactory ?? buildPanelProvider;

  final SessionFactory _factory;
  final PanelProviderFactory _providerFactory;
  final StreamController<SessionProgressEvent> _events =
      StreamController<SessionProgressEvent>.broadcast();

  ExplorationSession? _session;
  StreamSubscription<SessionProgressEvent>? _sub;
  ModelProvider? _provider;
  BroadcastTrajectorySink? _sink;
  Future<SessionTermination>? _run;

  /// `true` between [start] and [stop].
  bool get running => _session != null;

  /// Provider constructed for the active session (visible for tests).
  ModelProvider? get activeProvider => _provider;

  /// Forwards every [SessionProgressEvent] from the active session.
  Stream<SessionProgressEvent> get events => _events.stream;

  /// Live stream of [TrajectoryRecord]s emitted by the in-flight
  /// loop. Backed by a [BroadcastTrajectorySink] re-created per
  /// [start] call; the prior stream closes when its writer closes.
  /// Returns the empty broadcast when no session is running.
  Stream<TrajectoryRecord> get trajectory =>
      _sink?.records ?? const Stream<TrajectoryRecord>.empty();

  /// The in-flight [LoopDriver.runSession] future. `null` outside of
  /// `[start, stop]`. Resolves with a [SessionTermination] when the
  /// loop exits naturally; observers can attach `whenComplete` to
  /// re-enable the form on natural termination (vs. user `stop()`).
  Future<SessionTermination>? get runFuture => _run;

  /// Connect, subscribe, build the [ModelProvider] from [providerCfg]
  /// + [panelCfg.modelId], write the trajectory header, and kick off
  /// the perception-action loop via [ExplorationSession.run].
  ///
  /// Throws [StateError] if a session is already running, or if
  /// [providerCfg] is null — the panel cannot drive a real session
  /// without a configured model provider, and minting a session that
  /// can't run violates the AC.
  Future<void> start(
    PromptPanelConfig panelCfg, {
    ProviderConfig? providerCfg,
  }) async {
    if (_session != null) {
      throw StateError('session already running');
    }
    if (providerCfg == null) {
      throw StateError(
        'PromptPanelController.start requires providerCfg — '
        'configure a model provider before pressing Start.',
      );
    }
    final session = await _factory();
    _session = session;
    _sub = session.progress.listen(_events.add);
    await session.start(panelCfg.goal, panelCfg.toExplorationConfig());

    // Derive a stable session id from the clock so two concurrent
    // panels don't collide on the same conversation id.
    final sessionId =
        'panel-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final provider = _providerFactory(providerCfg, panelCfg.modelId, sessionId);
    _provider = provider;

    // Build a fresh trajectory pipeline for this run. The writer is
    // closed by LoopDriver's finally block, which in turn closes the
    // sink, so we don't manage sink lifetime here.
    final sink = BroadcastTrajectorySink();
    final writer = TrajectoryWriter(sink);
    _sink = sink;

    final handshake = session.handshake;
    await writer.writeHeader(SessionHeader(
      goal: panelCfg.goal,
      agentsMdHash: '',
      buildIdentifier: 'devtools',
      modelIdentifier: panelCfg.modelId,
      harnessVersion: 'devtools-ch8',
      plugins: <PluginManifestRecord>[
        for (final PluginManifestEntry p in handshake.plugins)
          PluginManifestRecord(
            namespace: p.namespace,
            packageVersion: 'unknown',
            contractVersion: handshake.contractVersion,
          ),
      ],
      config: <String, dynamic>{
        'enabled_plugins': panelCfg.enabledPluginNamespaces.toList()..sort(),
      },
    ));

    final Map<String, List<ToolDescriptor>> pluginTools = buildPluginTools(
      requested: panelCfg.enabledPluginNamespaces,
      handshake: handshake.plugins,
    );
    final DefaultLoopHost host = DefaultLoopHost.fromSession(
      session: session,
      coreTools: const <ToolDescriptor>[],
      pluginTools: pluginTools,
      goal: panelCfg.goal,
      agentsMd: '',
    );

    _run = session.run(host: host, provider: provider, writer: writer);
  }

  /// End the active session and tear down the subscription. No-op if
  /// nothing is running.
  Future<void> stop() async {
    final session = _session;
    if (session == null) return;
    // Wait for the loop to settle so the writer is closed (and the
    // broadcast sink with it) before we tear the session down. We
    // swallow loop errors so a model failure doesn't block teardown.
    final run = _run;
    if (run != null) {
      try {
        await run;
      } on Object {
        // Surface via runFuture / progress events; teardown proceeds.
      }
    }
    await session.end();
    await _sub?.cancel();
    _sub = null;
    _session = null;
    _provider = null;
    _sink = null;
    _run = null;
  }

  /// Stop and close the broadcast stream. After [dispose] the controller
  /// is unusable.
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
