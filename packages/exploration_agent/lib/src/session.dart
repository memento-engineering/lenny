/// Public lifecycle entrypoint for the exploration_agent harness.
///
/// Both `exploration_cli` (CLI frontend) and `exploration_devtools`
/// (DevTools extension panel) consume this same class — see PRD §6.2.
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' show VmService;

import 'loop_driver/loop_driver.dart';
import 'loop_driver/loop_host.dart';
import 'loop_driver/types.dart';
import 'memory/action_ring.dart';
import 'memory/running_summary.dart';
import 'memory/token_counter.dart';
import 'observation/diff_models.dart';
import 'observation/models.dart';
import 'observation/observation_differ.dart';
import 'prompt/prompt_assembler.dart';
import 'provider/model_provider.dart';
import 'session/observation_puller.dart';
import 'session/turn_event.dart';
import 'trajectory/writer.dart';
import 'types.dart';
import 'validation/action_validator.dart';
import 'vm_service_client.dart';

/// Owns the run lifecycle: connect, start, observe, act, end.
///
/// State transitions:
/// 1. `connect(uri)` — opens VM-service connection, returns instance.
/// 2. `start(goal, config)` — performs handshake, emits [SessionStarted].
/// 3. `observe()` / `act(...)` — repeatable until [end].
/// 4. `end()` — emits [SessionEnded], closes streams and connection.
///
/// `disablePlugin(...)` is callable any time after construction (used by
/// the auto-disable policy in .18) and emits [PluginAutoDisabled].
class ExplorationSession {
  ExplorationSession._(this._client) : _puller = ObservationPuller(_client);

  /// Test-only constructor that takes an already-built [VmServiceClient]
  /// (typically [VmServiceClient.forTest] wrapping a fake VmService).
  @visibleForTesting
  factory ExplorationSession.forTest(VmServiceClient client) {
    return ExplorationSession._(client);
  }

  /// Connect to the target app's VM service `vmServiceUri` and return a
  /// session instance. Call [start] before [observe] / [act].
  ///
  /// CLI-only: this routes through `package:vm_service/vm_service_io.dart`
  /// (transitively `dart:io`). Web callers (the DevTools extension) must
  /// use [fromVmService] with `serviceManager.service` instead.
  static Future<ExplorationSession> connect(Uri vmServiceUri) async {
    final client = await VmServiceClient.connect(vmServiceUri);
    return ExplorationSession._(client);
  }

  /// Wrap an already-connected [vm] (e.g. the DevTools extension's
  /// `serviceManager.service`) pinned to [isolateId]. Web-safe — no
  /// `dart:io`. Call [start] before [observe] / [act]. The caller owns
  /// the connection's lifetime; [end] still forwards [dispose].
  factory ExplorationSession.fromVmService(VmService vm, String isolateId) {
    return ExplorationSession._(VmServiceClient.fromVmService(vm, isolateId));
  }

  final VmServiceClient _client;
  final ObservationPuller _puller;
  final StreamController<SessionProgressEvent> _progress =
      StreamController<SessionProgressEvent>.broadcast();
  final StreamController<TurnEvent> _turnEvents =
      StreamController<TurnEvent>.broadcast();
  final Set<String> _disabled = <String>{};
  HandshakeResult? _handshake;
  bool _started = false;
  bool _ended = false;
  Observation _prevObservation = Observation.empty();

  /// Live progress events for the DevTools thinking panel and the CLI's
  /// transcript renderer.
  Stream<SessionProgressEvent> get progress => _progress.stream;

  /// Per-turn event stream consumed by the DevTools Thinking and Timeline
  /// panels (PRD §6.3). Events are forwarded by the loop driver via
  /// [emitTurnEvent].
  Stream<TurnEvent> get turnEvents => _turnEvents.stream;

  /// Internal: forward a per-turn event to [turnEvents]. The loop driver
  /// (cx6.18) calls this at PRD §10 step boundaries; ordinary callers
  /// should not invoke it directly.
  @internal
  void emitTurnEvent(TurnEvent e) {
    if (!_turnEvents.isClosed) {
      _turnEvents.add(e);
    }
  }

  /// Plugins that have been auto-disabled this session (via
  /// [disablePlugin]). Returned as an unmodifiable view.
  Set<String> get disabledPlugins => UnmodifiableSetView<String>(_disabled);

  /// The handshake result captured by [start]. Throws [StateError] if
  /// [start] has not yet completed.
  HandshakeResult get handshake {
    final h = _handshake;
    if (h == null) {
      throw StateError('handshake is unavailable until start() completes.');
    }
    return h;
  }

  /// Perform the binding handshake and capture contract version + plugin
  /// manifest. Emits [SessionStarted] exactly once on success.
  ///
  /// Throws [StateError] if called twice. Propagates
  /// [BindingNotInitializedError] from the underlying client when the
  /// target app's binding extension is absent.
  Future<void> start(String goal, ExplorationConfig config) async {
    if (_started) {
      throw StateError('Session already started');
    }
    final result = await _client.handshake();
    _handshake = result;
    _started = true;
    _emit(SessionStarted(goal));
  }

  /// Pull a stable observation from the binding. Routes through the
  /// session's [ObservationPuller] (the same path that backs
  /// [pullObservation] and [observeWithDiff]), so all three observation
  /// entrypoints share one VM-service call shape and one decode path.
  ///
  /// Does *not* mutate the per-session diff baseline (`_prevObservation`).
  /// Callers that need a diff use [observeWithDiff] instead.
  Future<Observation> observe({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) async {
    _ensureStarted('observe');
    return _puller.pull(policy: policy);
  }

  /// Internal accessor for the underlying [VmServiceClient]. Used by
  /// `DefaultLoopHost` to forward action execution from
  /// [LoopHost.executeAction]. Not part of the public API.
  @internal
  VmServiceClient get client => _client;

  /// Internal observation pull that runs through the session's
  /// [ObservationPuller] without mutating the per-session
  /// `_prevObservation` (the loop driver owns its own diff baseline).
  ///
  /// Used by `DefaultLoopHost.observe()` to back [LoopHost.observe].
  @internal
  Future<Observation> pullObservation({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) {
    _ensureStarted('pullObservation');
    return _puller.pull(policy: policy);
  }

  /// Pull a stable observation through the typed [ObservationPuller] and
  /// compute the per-turn structural diff against the previously stored
  /// observation. The first call diffs against [Observation.empty()]
  /// (PRD §11.3 first-turn behaviour: all-added).
  ///
  /// The returned diff is harness-authored and consumed verbatim by the
  /// next-prompt assembler (cx6.13) and the trajectory writer (cx6.19);
  /// validators (cx6.17) consume the typed `observation` field.
  Future<({Observation observation, ObservationDiff diff})> observeWithDiff({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) async {
    _ensureStarted('observeWithDiff');
    final Observation curr = await _puller.pull(policy: policy);
    final ObservationDiff diff =
        ObservationDiffer.diff(_prevObservation, curr);
    _prevObservation = curr;
    return (observation: curr, diff: diff);
  }

  /// Execute a tool action. The [action] map must contain `name`
  /// (String) and `args` (Map). Action validation is .17's job — this
  /// method only marshals the call.
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
    return _client.executeAction(rawName, args);
  }

  /// Record an auto-disable for [namespace] with a human-readable
  /// [reason]. Emits [PluginAutoDisabled]. Idempotent — disabling the
  /// same plugin twice still emits, so listeners can surface repeats.
  void disablePlugin(String namespace, String reason) {
    _disabled.add(namespace);
    _emit(PluginAutoDisabled(namespace, reason));
  }

  /// Close the session: emit [SessionEnded], close the progress stream,
  /// and dispose the underlying VM-service connection. No-op if [start]
  /// never ran.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    if (_started) {
      _emit(const SessionEnded());
    }
    await _progress.close();
    await _turnEvents.close();
    await _client.dispose();
  }

  /// Drive a full perception-action session via [LoopDriver].
  ///
  /// `start()` must have completed first. The caller supplies the host
  /// adapter (which exposes the merged tool list, AGENTS.md, the goal,
  /// and translates session/client calls), the model provider, and the
  /// trajectory writer. This convenience method constructs a
  /// [LoopDriver] with sensible defaults for the memory artifacts and
  /// the prompt assembler, runs the session, and returns the resulting
  /// [SessionTermination].
  ///
  /// Note: end() is *not* called automatically — callers typically end()
  /// after persisting the trajectory footer (which the driver writes
  /// before returning).
  Future<SessionTermination> run({
    required LoopHost host,
    required ModelProvider provider,
    required TrajectoryWriter writer,
    PromptAssembler? assembler,
    ActionValidator? validator,
    RunningSummary? summary,
    ActionRing? actions,
  }) async {
    _ensureStarted('run');
    final driver = LoopDriver(
      host: host,
      provider: provider,
      assembler: assembler ?? const PromptAssembler(),
      validator: validator ?? const ActionValidator(),
      writer: writer,
      summary: summary ?? RunningSummary(counter: WhitespaceTokenCounter()),
      actions: actions ?? ActionRing(),
      onTurnEvent: emitTurnEvent,
    );
    return driver.runSession();
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
}
