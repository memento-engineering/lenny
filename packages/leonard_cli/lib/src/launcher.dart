/// Boot a live target (Flutter app or pure-Dart program), discover the
/// Dart VM Service `ws://…/ws` URI from its run output, and hold the
/// process alive so a driver can attach.
///
/// This is the shared launch primitive behind two consumers:
///   * `leonard_drive up` — boot + expose + hold (the external-brain path:
///     the caller is the loop, so this just guarantees a live target and a
///     known URI, then gets out of the way).
///   * `leonard_cli --launch` — the autonomous loop reuses [launchTarget]
///     to obtain a URI before driving with lenny's own LLM.
///
/// It owns `dart:io` (process spawning) so it lives in `leonard_cli`, never
/// in `leonard_agent` (which must stay Flutter- and io-free). The pure
/// pieces — [parseVmServiceWsUri] and [buildRunnerInvocation] — are factored
/// out so they can be unit-tested without spawning anything.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// How to boot the target.
enum TargetRunner {
  /// `flutter run -d <device> -t <entrypoint>` — a Flutter app on a device.
  flutter,

  /// `dart run --enable-vm-service <entrypoint>` — any non-Flutter Dart
  /// program (e.g. an `ExplorationHost` runner). Has no device.
  dart,
}

/// Matches the Dart VM Service HTTP URL that `flutter run` ("A Dart VM
/// Service on … is available at: http://…") and `dart run` ("The Dart VM
/// service is listening on http://…") print on a line of their output.
///
/// Gated to a loopback host (127.0.0.1 / localhost / [::1]) — the VM
/// service is always served locally for these runners — so unrelated URLs
/// in build output (doc links, package hosts) are not mistaken for it.
final RegExp _vmServiceHttpRe = RegExp(
  r'(https?://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]*)',
);

/// Extract the VM-service `ws://…/ws` URI from a single line of runner
/// output, or `null` when the line carries no service URL.
///
/// Mirrors the canonical conversion `http://host:port/<token?>/` →
/// `ws://host:port/<token?>/ws` (https → wss). Token-free URLs (when auth
/// codes are disabled) collapse to `/ws`.
Uri? parseVmServiceWsUri(String line) {
  final RegExpMatch? m = _vmServiceHttpRe.firstMatch(line);
  if (m == null) return null;
  final Uri? http = Uri.tryParse(m.group(1)!);
  if (http == null) return null;
  return http.replace(
    scheme: http.isScheme('https') ? 'wss' : 'ws',
    pathSegments: <String>[
      ...http.pathSegments.where((String s) => s.isNotEmpty),
      'ws',
    ],
  );
}

/// An executable + its argument vector.
typedef RunnerInvocation = ({String executable, List<String> args});

/// Build the `(executable, args)` to spawn for [runner] driving
/// [entrypoint]. Pure and validating — no process is started here.
///
/// Throws [ArgumentError] on a contract violation rather than silently
/// switching modes:
///   * [device] with [TargetRunner.dart] — a pure-Dart program has no
///     device, so `-d` is meaningless.
///   * empty [entrypoint].
///
/// [vmServicePort] (default 0 → a random free port) and
/// [disableAuthCodes] apply to the `dart` runner; `flutter run` manages
/// its own service port and prints the full (tokened) URL we scrape.
RunnerInvocation buildRunnerInvocation({
  required TargetRunner runner,
  required String entrypoint,
  String? device,
  int vmServicePort = 0,
  bool disableAuthCodes = false,
  List<String> extraArgs = const <String>[],
}) {
  if (entrypoint.isEmpty) {
    throw ArgumentError.value(entrypoint, 'entrypoint', 'must not be empty');
  }
  switch (runner) {
    case TargetRunner.flutter:
      return (
        executable: 'flutter',
        args: <String>[
          'run',
          if (device != null && device.isNotEmpty) ...<String>['-d', device],
          '-t',
          entrypoint,
          ...extraArgs,
        ],
      );
    case TargetRunner.dart:
      if (device != null && device.isNotEmpty) {
        throw ArgumentError.value(
          device,
          'device',
          'a pure-Dart target (--runner dart) has no device; drop -d',
        );
      }
      return (
        executable: 'dart',
        args: <String>[
          'run',
          '--enable-vm-service=$vmServicePort',
          if (disableAuthCodes) '--disable-service-auth-codes',
          entrypoint,
          ...extraArgs,
        ],
      );
  }
}

/// The narrow contract the dual handle consumes from each per-process channel.
///
/// `LaunchHandle implements LaunchChannel` at runtime; a `FakeLaunchChannel`
/// implements it in unit tests so [launchDualTarget] / [DualLaunchHandle]
/// teardown can be exercised without spawning real processes. The interface
/// declares `shutdown({Duration grace})` with no default — implementers supply
/// it (the production [LaunchHandle] keeps its 8s default).
abstract class LaunchChannel {
  Uri get wsUri;
  Future<int> get exitCode;
  Future<void> shutdown({Duration grace});
}

/// A booted, held target: the discovered [wsUri], the live [process], and
/// a clean [shutdown].
class LaunchHandle implements LaunchChannel {
  LaunchHandle._(this.wsUri, this.process, this._runner, this._logSubs) {
    // Drain the log subscriptions for the life of the process, then release
    // them — keeps `onLog` flowing after handoff and stops the child
    // blocking on a full stdout/stderr pipe buffer.
    unawaited(process.exitCode.then((_) => _cancelLogs()));
  }

  /// The discovered VM-service `ws://…/ws` URI a driver attaches to.
  @override
  final Uri wsUri;

  /// The live runner process. It hosts the VM service / `LeonardBinding`;
  /// it must stay alive while anything drives the target.
  final Process process;

  final TargetRunner _runner;
  final List<StreamSubscription<String>> _logSubs;
  bool _shuttingDown = false;
  bool _logsCancelled = false;

  Future<void> _cancelLogs() async {
    if (_logsCancelled) return;
    _logsCancelled = true;
    for (final StreamSubscription<String> s in _logSubs) {
      await s.cancel();
    }
  }

  /// Completes with the process exit code once it terminates.
  @override
  Future<int> get exitCode => process.exitCode;

  /// Stop the target cleanly. For `flutter run`, send the interactive `q`
  /// quit first (which also tears the app down on-device) before falling
  /// back to signals; for `dart`, signal directly. Escalates to SIGKILL if
  /// the process does not exit within [grace]. Idempotent.
  @override
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) async {
    if (_shuttingDown) {
      await exitCode;
      return;
    }
    _shuttingDown = true;
    if (_runner == TargetRunner.flutter) {
      try {
        process.stdin.write('q');
        await process.stdin.flush();
      } on Object {
        // stdin may already be closed; fall through to signals.
      }
    } else {
      process.kill(ProcessSignal.sigterm);
    }
    try {
      await exitCode.timeout(grace);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await exitCode.timeout(grace);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _cancelLogs();
  }
}

/// Spawn [runner] on [entrypoint], stream its merged stdout/stderr to
/// [onLog] line-by-line, and complete once the VM-service URI is scraped.
///
/// Returns a [LaunchHandle] holding the live process — the caller decides
/// whether to drive it, hold it, or hand the URI off. Throws
/// [TimeoutException] if the service URI does not appear within [timeout]
/// (after killing the child), or [ArgumentError] for an invalid invocation
/// (see [buildRunnerInvocation]).
///
/// When [readyLine] is non-null, [launchTarget] ALSO waits for a line
/// containing that literal before returning — a second readiness gate beyond
/// the VM-service URI scrape. The native host prints its VM-service URL
/// *before* `AppiumBackend.connect()` runs, so the URL alone does not prove the
/// device session is live; the native host prints `LEONARD_HOST_READY` only
/// after `host.install()` succeeds. Threading the sentinel into the existing
/// `scan()` is the only safe mechanism: the process stdout/stderr are
/// single-subscription and already consumed here, so an external post-hoc
/// listener would throw "Stream already listened to". When [readyLine] is
/// `null` the behavior is byte-identical to before (single-target callers are
/// unaffected).
Future<LaunchHandle> launchTarget({
  required TargetRunner runner,
  required String entrypoint,
  String? device,
  int vmServicePort = 0,
  bool disableAuthCodes = false,
  List<String> extraArgs = const <String>[],
  String? readyLine,
  required void Function(String line) onLog,
  Duration timeout = const Duration(seconds: 180),
}) async {
  final RunnerInvocation inv = buildRunnerInvocation(
    runner: runner,
    entrypoint: entrypoint,
    device: device,
    vmServicePort: vmServicePort,
    disableAuthCodes: disableAuthCodes,
    extraArgs: extraArgs,
  );

  final Process proc = await Process.start(inv.executable, inv.args);
  final Completer<Uri> wsUri = Completer<Uri>();
  // Second readiness gate: completed when [readyLine] is observed. Left
  // pending (and never awaited) when readyLine is null.
  final Completer<void> ready = Completer<void>();
  // Absorb an orphaned error on the failure path where the wsUri await throws
  // FIRST (native host exits / times out before printing any VM-service URL):
  // the exit handler below errors `ready` too, but the `await ready.future`
  // listener (after the wsUri await) is never reached, so without this sink
  // that error lands in the root zone as an unhandled async error (exit 255),
  // racing the clean StateError the caller catches. A second listener is
  // harmless on the happy/safe paths (errors broadcast to all listeners), and
  // it is only attached when gated, keeping the readyLine==null path identical.
  if (readyLine != null) {
    unawaited(ready.future.catchError((Object _) {}));
  }

  void scan(String line) {
    onLog(line);
    if (!wsUri.isCompleted) {
      final Uri? ws = parseVmServiceWsUri(line);
      if (ws != null) wsUri.complete(ws);
    }
    if (readyLine != null && !ready.isCompleted && line.contains(readyLine)) {
      ready.complete();
    }
  }

  final List<StreamSubscription<String>> subs = <StreamSubscription<String>>[
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan),
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan),
  ];
  // If the process dies before printing a URI (or, when gated, before the
  // ready line), fail fast instead of hanging until the timeout.
  unawaited(
    proc.exitCode.then((int code) {
      if (!wsUri.isCompleted) {
        wsUri.completeError(
          StateError('runner exited (code $code) before a VM service URI'),
        );
      }
      if (readyLine != null && !ready.isCompleted) {
        ready.completeError(
          StateError(
            'native host exited (code $code) before LEONARD_HOST_READY',
          ),
        );
      }
    }),
  );

  try {
    final Uri ws = await wsUri.future.timeout(timeout);
    if (readyLine != null) {
      await ready.future.timeout(timeout);
    }
    // Hand the still-live subscriptions to the handle: `onLog` keeps
    // flowing after this returns, and the pipes keep draining.
    return LaunchHandle._(ws, proc, runner, subs);
  } on Object {
    for (final StreamSubscription<String> s in subs) {
      await s.cancel();
    }
    proc.kill(ProcessSignal.sigterm);
    rethrow;
  }
}

/// A held dual-channel launch: the Flutter target + the native host, both
/// pointed at the SAME device. Produced by [launchDualTarget]; held by
/// `leonard_drive up`; consumed (its two ws URIs) by the agent's multi-host
/// attach.
///
/// Holds two [LaunchChannel]s: a [LaunchHandle] for each at runtime, or a
/// `FakeLaunchChannel` in unit tests (the interface exists only for that seam).
class DualLaunchHandle {
  DualLaunchHandle._(
    this.flutter,
    this.native,
    this.deviceId,
    this._owned,
    this._simctlShutdownFn,
  );

  /// @visibleForTesting — build the composite directly from two channels so a
  /// unit test can drive [shutdown] ordering against fake channels without
  /// spawning. Production code uses [launchDualTarget]. [simctlShutdown]
  /// overrides the real `xcrun simctl shutdown` hook so the owned-sim teardown
  /// leg is assertable in the unit tier without spawning `xcrun`.
  @visibleForTesting
  factory DualLaunchHandle.forTest({
    required LaunchChannel flutter,
    required LaunchChannel native,
    required String deviceId,
    bool owned = false,
    Future<void> Function(String udid)? simctlShutdown,
  }) => DualLaunchHandle._(
    flutter,
    native,
    deviceId,
    owned,
    simctlShutdown ?? _simctlShutdown,
  );

  /// The Flutter target channel — `flutter run -d <deviceId>`.
  /// `flutter.wsUri` is the design's `flutterWsUri`.
  final LaunchChannel flutter;

  /// The native channel — the held leonard_native host process.
  /// `native.wsUri` is the design's `nativeEndpoint`.
  final LaunchChannel native;

  /// The shared simulator udid both channels target — the design's `deviceId`
  /// and the shared-identity invariant. Equals `flutter run -d <deviceId>` AND
  /// the native host's `--udid`.
  final String deviceId;

  /// True iff `up` booted the sim itself (`--boot-sim`); drives sim shutdown.
  final bool _owned;

  /// The sim-shutdown hook run (only) when `_owned`. Real `_simctlShutdown` at
  /// runtime; a recording stub in unit tests (see [DualLaunchHandle.forTest]).
  final Future<void> Function(String udid) _simctlShutdownFn;

  /// Memoizes the in-flight teardown so re-entrant/concurrent [shutdown] calls
  /// await the same run instead of re-running the legs (true idempotency).
  Future<void>? _shutdownFuture;

  /// Convenience alias for the handoff: the Flutter/primary ws URI.
  Uri get flutterWsUri => flutter.wsUri;

  /// Convenience alias for the handoff: the native ws URI.
  Uri get nativeEndpoint => native.wsUri;

  /// Fires when EITHER channel exits (so the holder can tear the other down).
  Future<int> get exitCode =>
      Future.any(<Future<int>>[flutter.exitCode, native.exitCode]);

  /// Dependency-reverse teardown: native session first (releases the WebDriver
  /// / WDA session via the host's dispose), then the Flutter target (whose `q`
  /// uninstall is safe only AFTER the WDA session is released), then — only if
  /// owned — the simulator. Strictly serial, idempotent (a re-entrant or
  /// concurrent call awaits the in-flight run rather than re-running any leg),
  /// and every leg runs in its own try/catch so all legs run even when one
  /// throws (teardown swallows on purpose). The Appium server is never stopped
  /// (attach).
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) =>
      _shutdownFuture ??= _shutdown(grace);

  Future<void> _shutdown(Duration grace) async {
    try {
      await native.shutdown(grace: grace);
    } on Object {
      // best-effort teardown
    }
    try {
      await flutter.shutdown(grace: grace);
    } on Object {
      // best-effort teardown
    }
    if (_owned) {
      try {
        await _simctlShutdownFn(deviceId);
      } on Object {
        // best-effort teardown
      }
    }
  }
}

/// The spawn seam for [launchDualTarget] — assignment-compatible with
/// [launchTarget], which is its production default. A unit test injects a
/// stub returning canned / throwing [LaunchChannel]s so the dual lifecycle can
/// be exercised without spawning real processes.
typedef TargetSpawner =
    Future<LaunchChannel> Function({
      required TargetRunner runner,
      required String entrypoint,
      String? device,
      bool disableAuthCodes,
      List<String> extraArgs,
      String? readyLine,
      required void Function(String) onLog,
      required Duration timeout,
    });

/// Boot a dual-channel launch: a Flutter target on [udid] plus the leonard
/// native host against the SAME [udid] + [app], discover both VM-service ws
/// URIs, and assemble a [DualLaunchHandle] holding both.
///
/// The shared device identity is the invariant: the ONE [udid] String is
/// threaded into both `flutter run -d <udid>` and the native host's `--udid` —
/// never derived separately. The native leg is gated on `LEONARD_HOST_READY`
/// (so the returned handle proves the Appium device session is live, not just
/// that the VM service is up).
///
/// ATTACH semantics: this probes the operator-provisioned Appium server
/// ([appiumServer]); it never spawns it. When [bootSim] is set it OWNS sim
/// boot (`xcrun simctl boot <udid>`) and the resulting handle owns sim shutdown
/// (default OFF → attach to an operator-booted sim).
///
/// Compensation is BOUNDED: if the native boot throws after the Flutter boot
/// succeeds, the already-booted Flutter channel is torn down with a 2s grace
/// (so a failed boot never hangs the full default-grace window) before the
/// error is rethrown.
Future<DualLaunchHandle> launchDualTarget({
  required String flutterEntrypoint,
  required String udid,
  required String app,
  required String nativeHostPath,
  Uri? appiumServer,
  String platform = 'ios',
  bool bootSim = false,
  required void Function(String) onLog,
  Duration timeout = const Duration(seconds: 180),
  @visibleForTesting TargetSpawner spawn = launchTarget,
}) async {
  final Uri server = appiumServer ?? Uri.parse('http://127.0.0.1:4723');

  if (bootSim) {
    await _bootSim(udid);
  }
  await _probeAppium(server);

  // The shared udid feeds BOTH legs — one String, never derived twice.
  final LaunchChannel flutter = await spawn(
    runner: TargetRunner.flutter,
    entrypoint: flutterEntrypoint,
    device: udid,
    disableAuthCodes: false,
    extraArgs: const <String>[],
    readyLine: null,
    onLog: onLog,
    timeout: timeout,
  );

  final LaunchChannel native;
  try {
    native = await spawn(
      runner: TargetRunner.dart,
      entrypoint: nativeHostPath,
      device: null,
      disableAuthCodes: true,
      extraArgs: <String>[
        '--server',
        server.toString(),
        '--udid',
        udid,
        '--app',
        app,
        '--platform',
        platform,
      ],
      readyLine: 'LEONARD_HOST_READY',
      onLog: onLog,
      timeout: timeout,
    );
  } on Object {
    // launchTarget kills only its OWN child on failure, so the already-booted
    // Flutter channel would otherwise leak. Tear it down with a BOUNDED grace
    // so a failed boot never hangs the full default-grace window, then rethrow.
    // The cleanup is itself guarded so the ORIGINAL boot error always wins (it
    // carries the `LEONARD_HOST_READY` precondition message the operator sees).
    try {
      await flutter.shutdown(grace: const Duration(seconds: 2));
    } on Object {
      // swallow — the original native-boot error must propagate
    }
    rethrow;
  }

  return DualLaunchHandle._(flutter, native, udid, bootSim, _simctlShutdown);
}

/// Probe the operator-provisioned Appium server with `GET <server>/status`
/// (3s connect, 5s read). Throws [StateError] with an actionable message when
/// the server is unreachable — converting the otherwise opaque "native host
/// exited before LEONARD_HOST_READY" into a clear precondition error. ATTACH:
/// this never spawns Appium.
Future<void> _probeAppium(Uri server) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest req = await client.getUrl(
      server.replace(path: '${server.path}/status'),
    );
    final HttpClientResponse res = await req.close().timeout(
      const Duration(seconds: 5),
    );
    await res.drain<void>(null);
    if (res.statusCode < 200 || res.statusCode >= 500) {
      throw StateError('Appium /status returned ${res.statusCode}');
    }
  } on Object {
    throw StateError(
      'Appium not reachable at $server — start it (operator-provisioned) '
      'or pass --appium-server',
    );
  } finally {
    client.close(force: true);
  }
}

/// Boot the simulator [udid] (`xcrun simctl boot`). Idempotent: an
/// already-booted sim ("Unable to boot … current state: Booted") is success.
/// The ONE ownership the dual path may take, behind `--boot-sim`.
Future<void> _bootSim(String udid) async {
  final ProcessResult r = await Process.run('xcrun', <String>[
    'simctl',
    'boot',
    udid,
  ]);
  if (r.exitCode == 0) return;
  final String err = '${r.stdout}${r.stderr}';
  if (err.contains('Booted') || err.toLowerCase().contains('already booted')) {
    return; // idempotent: already booted is success
  }
  throw StateError('xcrun simctl boot $udid failed: ${err.trim()}');
}

/// Shut the simulator [udid] down (`xcrun simctl shutdown`). Best-effort and
/// BOUNDED — only ever called on teardown when the launch owned sim boot. A
/// wedged CoreSimulator daemon can make `simctl shutdown` hang, so the `xcrun`
/// child is killed if it does not exit within [grace] (mirroring the
/// SIGTERM→SIGKILL bound the channel legs already have) — teardown never blocks
/// unbounded.
Future<void> _simctlShutdown(
  String udid, {
  Duration grace = const Duration(seconds: 8),
}) async {
  final Process p = await Process.start('xcrun', <String>[
    'simctl',
    'shutdown',
    udid,
  ]);
  try {
    await p.exitCode.timeout(grace);
  } on TimeoutException {
    p.kill(ProcessSignal.sigkill);
  }
}
