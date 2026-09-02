/// The long-lived panel and sample-app harness.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show parentPath;
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;

import 'selfdrive_circuit.dart';
import 'selfdrive_preflight.dart' show EnvLookup, kSelfdriveClearedModelKey;

/// The observable surface of a launched harness process.
class HarnessProcess {
  /// Creates a process observation surface.
  const HarnessProcess({
    required this.diagnostics,
    required this.exitCode,
    required this.kill,
  });

  /// Stderr lines, where the harness publishes `KEY=value` diagnostics.
  final Stream<String> diagnostics;

  /// Completes when the harness exits.
  final Future<int> exitCode;

  /// Idempotently terminates the harness process group.
  final Future<void> Function() kill;
}

/// The values required to launch a harness.
class HarnessLaunchRequest {
  /// Creates a launch request.
  const HarnessLaunchRequest({
    required this.repoRoot,
    required this.device,
    required this.artifactDir,
    required this.env,
  });

  /// Workspace root containing the harness script.
  final String repoRoot;

  /// Sample-app device id.
  final String device;

  /// Run directory into which the harness writes logs.
  final String artifactDir;

  /// Additional process environment.
  final Map<String, String> env;
}

/// Injectable process-launch seam.
typedef HarnessLauncher =
    Future<HarnessProcess> Function(HarnessLaunchRequest request);

/// Folds the harness's four URI publications into a readiness ledger.
class SelfdriveUriLedger {
  final Map<String, String> _published = <String, String>{};

  /// URIs published so far.
  Map<String, String> get published =>
      Map<String, String>.unmodifiable(_published);

  /// Unpublished keys in contract order.
  List<String> get missing => <String>[
    for (final String key in kSelfdriveUriKeys)
      if (!_published.containsKey(key)) key,
  ];

  /// Whether every required URI has been published.
  bool get isReady => missing.isEmpty;

  /// Absorbs one diagnostic line, ignoring noise and empty publications.
  void absorb(String line) {
    final int split = line.indexOf('=');
    if (split <= 0) return;
    final String key = line.substring(0, split).trim();
    if (!kSelfdriveUriKeys.contains(key)) return;
    final String value = line.substring(split + 1).trim();
    if (value.isEmpty) return;
    _published[key] = value;
  }
}

/// A held lease over the live harness and its run directory.
class PanelHarnessLease {
  /// Creates a harness lease.
  const PanelHarnessLease({required this.process, required this.runDir});

  /// Live harness process.
  final HarnessProcess process;

  /// `trajectories/panel-selfdrive-*` run directory.
  final String runDir;
}

/// Launches the existing panel self-drive harness script.
Future<HarnessProcess> launchPanelHarness(HarnessLaunchRequest request) async {
  final Process process = await Process.start(
    'bash',
    <String>['tool/run_panel_selfdrive.sh', request.device],
    workingDirectory: request.repoRoot,
    environment: <String, String>{
      ...request.env,
      'PANEL_SELFDRIVE_ARTIFACT_DIR': request.artifactDir,
    },
  );
  final Stream<String> diagnostics = process.stderr
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  return HarnessProcess(
    diagnostics: diagnostics,
    exitCode: process.exitCode,
    kill: () async {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode;
    },
  );
}

/// Acquires the live harness and reports ready only after all four URIs exist.
class PanelHarnessCapability extends LeaseCapability<PanelHarnessLease> {
  /// Creates the capability over injectable launch, clock, and environment
  /// seams.
  const PanelHarnessCapability({
    HarnessLauncher launcher = launchPanelHarness,
    DateTime Function() clock = _now,
    EnvLookup env = _systemEnv,
    Duration readyTimeout = const Duration(minutes: 5),
  }) : _launcher = launcher,
       _clock = clock,
       _env = env,
       _readyTimeout = readyTimeout;

  static DateTime _now() => DateTime.now().toUtc();
  static String? _systemEnv(String name) => Platform.environment[name];

  final HarnessLauncher _launcher;
  final DateTime Function() _clock;
  final EnvLookup _env;
  final Duration _readyTimeout;

  @override
  Future<LeaseResolution<PanelHarnessLease>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    final Workspace? workspace = context
        .getInheritedSeedOfExactType<Workspace>();
    final Bead? bead = context.getInheritedSeedOfExactType<Bead>();
    final SelfdriveOrder? order = bead == null
        ? null
        : SelfdriveOrder.fromBead(bead);
    if (workspace == null || order == null) {
      return const LeaseUnavailable<PanelHarnessLease>(
        'selfdrive panel-harness: no ambient Workspace or no selfdrive order',
      );
    }
    final SiblingView siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final String pinned =
        siblings.resultOf(
          '${parentPath(args.nodePath)}/$kSelfdrivePreflightStep',
        )[kSelfdriveClearedModelKey] ??
        order.innerModelId;
    final String runDir = p.join(
      workspace.workspaceDir,
      'packages',
      'leonard_cli',
      'trajectories',
      'panel-selfdrive-${_stamp(_clock())}',
    );
    Directory(runDir).createSync(recursive: true);
    try {
      final HarnessProcess process = await _launcher(
        HarnessLaunchRequest(
          repoRoot: workspace.workspaceDir,
          device: order.device,
          artifactDir: runDir,
          env: <String, String>{
            'SWIFT_INFER_ENDPOINT': _env('SWIFT_INFER_ENDPOINT') ?? '',
            'SWIFT_INFER_AGENT_TOKEN': _env('SWIFT_INFER_AGENT_TOKEN') ?? '',
            'SWIFT_INFER_MODEL': pinned,
            'PANEL_SELFDRIVE_MODEL_ID': pinned,
          },
        ),
      );
      if (args.cancel.isCancelled) {
        await process.kill();
        return const LeaseUnavailable<PanelHarnessLease>('cancelled');
      }
      return LeaseBound<PanelHarnessLease>(
        PanelHarnessLease(process: process, runDir: runDir),
      );
    } on Object catch (error) {
      return LeaseUnavailable<PanelHarnessLease>(
        'selfdrive panel-harness: launch failed: $error',
      );
    }
  }

  @override
  Future<StepOutcome> dispatchOn(
    PanelHarnessLease handle,
    TreeContext context,
    StepArgs args,
  ) async {
    final SelfdriveUriLedger ledger = SelfdriveUriLedger();
    final IOSink log = File(
      p.join(handle.runDir, 'harness.log'),
    ).openWrite(mode: FileMode.append);
    final Completer<void> ready = Completer<void>();
    final StreamSubscription<String> lines = handle.process.diagnostics.listen(
      (String line) {
        log.writeln(line);
        ledger.absorb(line);
        if (ledger.isReady && !ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!ready.isCompleted) ready.completeError(error, stackTrace);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('harness output closed'));
        }
      },
    );
    unawaited(
      handle.process.exitCode.then((int code) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('harness exited with $code'));
        }
      }),
    );
    try {
      await ready.future.timeout(_readyTimeout);
    } on Object catch (error) {
      return Failed(
        'selfdrive panel-harness never published ${ledger.missing.join(', ')} '
        '($error)',
      );
    } finally {
      await lines.cancel();
      await log.flush();
      await log.close();
    }
    if (args.cancel.isCancelled) return const Failed('cancelled');
    return Ok(<String, String>{
      ...ledger.published,
      kSelfdriveRunDirKey: handle.runDir,
    });
  }

  @override
  Future<void> release(PanelHarnessLease handle) => handle.process.kill();
}

String _stamp(DateTime at) =>
    at.toIso8601String().replaceAll(RegExp(r'[:\-]'), '').split('.').first;
