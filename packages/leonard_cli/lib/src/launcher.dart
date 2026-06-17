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

/// A booted, held target: the discovered [wsUri], the live [process], and
/// a clean [shutdown].
class LaunchHandle {
  LaunchHandle._(this.wsUri, this.process, this._runner, this._logSubs) {
    // Drain the log subscriptions for the life of the process, then release
    // them — keeps `onLog` flowing after handoff and stops the child
    // blocking on a full stdout/stderr pipe buffer.
    unawaited(process.exitCode.then((_) => _cancelLogs()));
  }

  /// The discovered VM-service `ws://…/ws` URI a driver attaches to.
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
  Future<int> get exitCode => process.exitCode;

  /// Stop the target cleanly. For `flutter run`, send the interactive `q`
  /// quit first (which also tears the app down on-device) before falling
  /// back to signals; for `dart`, signal directly. Escalates to SIGKILL if
  /// the process does not exit within [grace]. Idempotent.
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
Future<LaunchHandle> launchTarget({
  required TargetRunner runner,
  required String entrypoint,
  String? device,
  int vmServicePort = 0,
  bool disableAuthCodes = false,
  List<String> extraArgs = const <String>[],
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

  void scan(String line) {
    onLog(line);
    if (wsUri.isCompleted) return;
    final Uri? ws = parseVmServiceWsUri(line);
    if (ws != null) wsUri.complete(ws);
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
  // If the process dies before printing a URI, fail fast instead of
  // hanging until the timeout.
  unawaited(
    proc.exitCode.then((int code) {
      if (!wsUri.isCompleted) {
        wsUri.completeError(
          StateError('runner exited (code $code) before a VM service URI'),
        );
      }
    }),
  );

  try {
    final Uri ws = await wsUri.future.timeout(timeout);
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
