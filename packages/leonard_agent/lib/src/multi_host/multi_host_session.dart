/// Multi-host attach/merge/route façade (m3, `lenny-qxx.3`).
///
/// Generalizes the single-host [LeonardSession] (one VM-service endpoint,
/// one isolate, one handshake, one diff baseline) to **N** hosts. A
/// [MultiHostSession] holds one [_HostChannel] per attached host — each the
/// per-host bundle `{VmServiceClient, ObservationPuller, HandshakeResult}`,
/// i.e. exactly the per-session state [LeonardSession] holds for N=1 — and:
///
/// 1. attaches one [VmServiceClient] per endpoint ([connectAll] owns each;
///    [fromVmServices] borrows each),
/// 2. merges every host's handshake into one [HandshakeResult] (namespace
///    union, capability union de-duped first-seen, primary contract
///    version) and a namespace→channel routing table,
/// 3. merges every host's observation into one [Observation]
///    (`mergeObservations`), and
/// 4. routes each `<namespace>.<tool>` action to the owning channel.
///
/// Pure of `dart:io` and Flutter: the owning [connectAll] path routes
/// through the existing [VmServiceClient.connect] seam (the only place in
/// `lib/` that transitively touches `dart:io`); this file adds no new
/// `dart:io` import.
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' show VmService;

import '../loop_driver/loop_driver.dart';
import '../loop_driver/loop_host.dart';
import '../loop_driver/session_surface.dart';
import '../loop_driver/types.dart';
import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../observation/observation_differ.dart';
import '../prompt/conversation_builder.dart';
import '../provider/model_provider.dart';
import '../session/observation_puller.dart';
import '../session/turn_event.dart';
import '../trajectory/writer.dart';
import '../types.dart';
import '../validation/action_validator.dart';
import '../vm_service_client.dart';
import 'multi_host_errors.dart';
import 'observation_merge.dart';

/// One host to attach: its diagnostic [label] + the ws:// [uri] to reach
/// it. Exported so CLI callers can name endpoints (e.g. `flutter`/`native`).
class HostAttachment {
  const HostAttachment({required this.label, required this.uri});

  /// Diagnostics only — surfaced in collision errors. E.g. `flutter` /
  /// `native`.
  final String label;

  /// The host's VM-service ws:// URI.
  final Uri uri;
}

/// The per-host bundle: one client, one puller, one handshake. Mirrors the
/// per-session state [LeonardSession] holds for N=1, lifted to one-per-host.
class _HostChannel {
  _HostChannel({required this.label, required this.client})
    : puller = ObservationPuller(client);

  final String label;
  final VmServiceClient client;
  final ObservationPuller puller;

  /// Captured by [MultiHostSession.start]; null before then.
  HandshakeResult? handshake;
}

/// N-host generalization of [LeonardSession]. Implements [SessionSurface]
/// so `DefaultLoopHost`/`bringUpSession` drive it identically to a
/// single-host session.
class MultiHostSession implements SessionSurface {
  MultiHostSession._(this._channels);

  /// Owning attach: open one [VmServiceClient] per [hosts] endpoint (each
  /// pins its own first isolate), in the order given. CLI-only — routes
  /// through [VmServiceClient.connect] (transitively `dart:io`), exactly
  /// like [LeonardSession.connect]. Call [start] before observe/act.
  ///
  /// The dual case is just
  /// `connectAll([HostAttachment(label:'flutter', uri:flutterWsUri),
  /// HostAttachment(label:'native', uri:nativeEndpoint)])`.
  static Future<MultiHostSession> connectAll(List<HostAttachment> hosts) async {
    if (hosts.isEmpty) {
      throw ArgumentError.value(
        hosts,
        'hosts',
        'connectAll requires at least one host',
      );
    }
    // Connect in attach order so channel index 0 is the primary (Flutter).
    final List<_HostChannel> channels = <_HostChannel>[];
    try {
      for (final HostAttachment h in hosts) {
        final VmServiceClient client = await VmServiceClient.connect(h.uri);
        channels.add(_HostChannel(label: h.label, client: client));
      }
    } on Object {
      // A later connect failed; tear down the channels already opened so we
      // never leak owned VM-service connections.
      for (final _HostChannel ch in channels) {
        await ch.client.dispose();
      }
      rethrow;
    }
    return MultiHostSession._(channels);
  }

  /// Borrowed attach (web-safe / DevTools): wrap already-connected
  /// `(VmService, isolateId)` pairs. Mirrors [LeonardSession.fromVmService];
  /// each channel's client is BORROWED so [end] never tears down a
  /// connection it did not open.
  factory MultiHostSession.fromVmServices(
    List<({String label, VmService vm, String isolateId})> hosts,
  ) {
    if (hosts.isEmpty) {
      throw ArgumentError.value(
        hosts,
        'hosts',
        'fromVmServices requires at least one host',
      );
    }
    return MultiHostSession._(<_HostChannel>[
      for (final ({String label, VmService vm, String isolateId}) h in hosts)
        _HostChannel(
          label: h.label,
          client: VmServiceClient.fromVmService(h.vm, h.isolateId),
        ),
    ]);
  }

  /// Test-only constructor: wrap already-built [clients] (typically
  /// [VmServiceClient.forTest]). Channel labels default to `host0`,
  /// `host1`, … in order.
  @visibleForTesting
  factory MultiHostSession.forTest(List<VmServiceClient> clients) {
    if (clients.isEmpty) {
      throw ArgumentError.value(
        clients,
        'clients',
        'forTest requires at least one client',
      );
    }
    int i = 0;
    return MultiHostSession._(<_HostChannel>[
      for (final VmServiceClient c in clients)
        _HostChannel(label: 'host${i++}', client: c),
    ]);
  }

  final List<_HostChannel> _channels;
  final StreamController<SessionProgressEvent> _progress =
      StreamController<SessionProgressEvent>.broadcast();
  final StreamController<TurnEvent> _turnEvents =
      StreamController<TurnEvent>.broadcast();
  final Set<String> _disabled = <String>{};
  final Map<String, _HostChannel> _route = <String, _HostChannel>{};
  HandshakeResult? _merged;
  bool _started = false;
  bool _ended = false;
  Observation _prevObservation = Observation.empty();

  /// Live progress events (mirrors [LeonardSession.progress]).
  Stream<SessionProgressEvent> get progress => _progress.stream;

  /// Per-turn event stream (mirrors [LeonardSession.turnEvents]).
  Stream<TurnEvent> get turnEvents => _turnEvents.stream;

  /// Forward a per-turn event to [turnEvents]. The loop driver calls this
  /// at step boundaries; ordinary callers should not invoke it directly.
  @internal
  void emitTurnEvent(TurnEvent e) {
    if (!_turnEvents.isClosed) {
      _turnEvents.add(e);
    }
  }

  /// Extensions auto-disabled this session (unmodifiable view).
  Set<String> get disabledExtensions => UnmodifiableSetView<String>(_disabled);

  /// The merged handshake captured by [start]. Throws [StateError] before
  /// [start] completes (mirrors [LeonardSession.handshake]).
  @override
  HandshakeResult get handshake {
    final HandshakeResult? h = _merged;
    if (h == null) {
      throw StateError('handshake is unavailable until start() completes.');
    }
    return h;
  }

  /// Perform the per-channel handshake, run the namespace-collision check,
  /// build the merged [HandshakeResult] + namespace→channel routing table,
  /// and emit [SessionStarted]. Throws [StateError] if called twice;
  /// throws [MultiHostNamespaceCollision] if two hosts claim a namespace.
  Future<void> start(String goal, LeonardConfig config) async {
    if (_started) {
      throw StateError('Session already started');
    }
    // Rebuild routing from scratch: a prior start() that threw a collision
    // mid-loop (below) leaves _started false but _route partially populated, so
    // a retry-after-detach must not route against stale entries.
    _route.clear();
    // Per-channel handshake, concurrently (one per VM-service endpoint).
    await Future.wait(<Future<void>>[
      for (final _HostChannel ch in _channels)
        ch.client.handshake().then((HandshakeResult r) => ch.handshake = r),
    ]);

    // Collision check over MANIFEST namespaces (handshake.extensions[].
    // namespace) — fail fast before the loop / before any observation.
    final Map<String, String> owner = <String, String>{}; // ns -> label
    for (final _HostChannel ch in _channels) {
      for (final ExtensionManifestEntry e in ch.handshake!.extensions) {
        final String? existing = owner[e.namespace];
        if (existing != null && existing != ch.label) {
          throw MultiHostNamespaceCollision(e.namespace, <String>[
            existing,
            ch.label,
          ]);
        }
        owner[e.namespace] = ch.label;
        _route[e.namespace] = ch;
      }
    }

    _merged = _mergeHandshakes(_channels);
    _started = true;
    _emit(SessionStarted(goal));
  }

  /// Pull a stable observation from EVERY channel under [policy]
  /// concurrently and fold into one merged [Observation] (the union
  /// interpretation: "stable" = all hosts idle, the slowest gates the
  /// turn). Does NOT mutate the diff baseline; use [observeWithDiff] for a
  /// diff. Mirrors [LeonardSession.observe].
  Future<Observation> observe({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) async {
    _ensureStarted('observe');
    return _pullMerged(policy);
  }

  /// [SessionSurface] observation pull (loop-host facing) — same merged
  /// path as [observe], no baseline mutation.
  @override
  Future<Observation> pullObservation({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) {
    _ensureStarted('pullObservation');
    return _pullMerged(policy);
  }

  /// Pull the merged observation and compute the per-turn structural diff
  /// against the single merged [_prevObservation] baseline. Mirrors
  /// [LeonardSession.observeWithDiff].
  Future<({Observation observation, ObservationDiff diff})> observeWithDiff({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) async {
    _ensureStarted('observeWithDiff');
    final Observation curr = await _pullMerged(policy);
    final ObservationDiff diff = ObservationDiffer.diff(_prevObservation, curr);
    _prevObservation = curr;
    return (observation: curr, diff: diff);
  }

  /// Route a `<namespace>.<tool>` action to the owning channel's client.
  /// Splits on the FIRST dot (identical to [VmServiceClient.executeAction]);
  /// throws [ArgumentError] on a malformed name and
  /// [MultiHostUnknownNamespace] synchronously (before any wire call) on an
  /// unmapped namespace.
  @override
  Future<Map<String, dynamic>> executeAction(
    String name,
    Map<String, dynamic> args,
  ) {
    _ensureStarted('executeAction');
    final int dot = name.indexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      throw ArgumentError.value(
        name,
        'name',
        'action name must be qualified as <namespace>.<tool>',
      );
    }
    final String ns = name.substring(0, dot);
    final _HostChannel? ch = _route[ns];
    if (ch == null) {
      throw MultiHostUnknownNamespace(ns, _route.keys.toList()..sort());
    }
    return ch.client.executeAction(name, args);
  }

  /// Execute a tool action. The [action] map must contain `name` (String)
  /// and `args` (Map). Marshals exactly like [LeonardSession.act], then
  /// routes via [executeAction].
  Future<Map<String, dynamic>> act(Map<String, dynamic> action) async {
    _ensureStarted('act');
    final Object? rawName = action['name'];
    if (rawName is! String) {
      throw ArgumentError.value(
        action,
        'action',
        'action.name must be a String',
      );
    }
    final Object? rawArgs = action['args'];
    final Map<String, dynamic> args;
    if (rawArgs == null) {
      args = const <String, dynamic>{};
    } else if (rawArgs is Map) {
      args = rawArgs.cast<String, dynamic>();
    } else {
      throw ArgumentError.value(
        action,
        'action',
        'action.args must be a Map<String, dynamic> or null',
      );
    }
    return executeAction(rawName, args);
  }

  /// Record an auto-disable for [namespace]. Per-namespace, which is
  /// already per-host (each namespace maps to one channel). The routing
  /// table is unaffected — disable hides tools from `mergedTools`, it does
  /// not unmap the route. Emits [ExtensionAutoDisabled].
  @override
  void disableExtension(String namespace, String reason) {
    _disabled.add(namespace);
    _emit(ExtensionAutoDisabled(namespace, reason));
  }

  /// Close the session: emit [SessionEnded], close the streams, and dispose
  /// EVERY channel's client (each [VmServiceClient.dispose] no-ops on a
  /// borrowed connection). No-op if already ended.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    if (_started) {
      _emit(const SessionEnded());
    }
    await _progress.close();
    await _turnEvents.close();
    for (final _HostChannel ch in _channels) {
      await ch.client.dispose();
    }
  }

  /// Drive a full perception-action session via [LoopDriver] over the
  /// supplied [host]. Mirrors [LeonardSession.run] so the autonomous path
  /// can drive a multi-host session in m5 without rework. The loop driver
  /// is unchanged.
  Future<SessionTermination> run({
    required LoopHost host,
    required ModelProvider provider,
    required TrajectoryWriter writer,
    ConversationBuilder? conversation,
    ActionValidator? validator,
    int tokenBudget = 32000,
    Duration? turnBudget,
  }) async {
    _ensureStarted('run');
    final Duration effectiveTurnBudget =
        turnBudget ?? const Duration(seconds: 120);
    final driver = LoopDriver(
      host: host,
      provider: provider,
      conversation:
          conversation ??
          ConversationBuilder(
            systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
            tools: host.mergedTools(),
          ),
      validator: validator ?? const ActionValidator(),
      writer: writer,
      onTurnEvent: emitTurnEvent,
      tokenBudget: tokenBudget,
      turnBudget: effectiveTurnBudget,
    );
    return driver.runSession();
  }

  Future<Observation> _pullMerged(StabilityPolicy policy) async {
    // One policy, all hosts, join-on-all (Future.wait). The list preserves
    // attach order so index 0 (Flutter) is the merge primary.
    final List<Observation> perHost = await Future.wait(<Future<Observation>>[
      for (final _HostChannel ch in _channels) ch.puller.pull(policy: policy),
    ]);
    return mergeObservations(perHost);
  }

  void _ensureStarted(String op) {
    if (!_started) {
      throw StateError('start() must complete before $op().');
    }
  }

  void _emit(SessionProgressEvent event) {
    if (!_progress.isClosed) {
      _progress.add(event);
    }
  }

  /// Build the merged handshake: namespace union (attach order, then
  /// handshake order), capability union de-duped FIRST-SEEN, contract
  /// version from the PRIMARY (first) channel.
  static HandshakeResult _mergeHandshakes(List<_HostChannel> channels) {
    final List<ExtensionManifestEntry> extensions = <ExtensionManifestEntry>[
      for (final _HostChannel ch in channels) ...ch.handshake!.extensions,
    ];
    final List<String> capabilities = <String>[];
    final Set<String> seen = <String>{};
    for (final _HostChannel ch in channels) {
      for (final String cap in ch.handshake!.capabilities) {
        if (seen.add(cap)) capabilities.add(cap);
      }
    }
    return HandshakeResult(
      contractVersion: channels.first.handshake!.contractVersion,
      extensions: extensions,
      capabilities: capabilities,
    );
  }
}
