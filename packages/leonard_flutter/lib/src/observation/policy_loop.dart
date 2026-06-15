import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../contract/types.dart';
import '../stability/framework_busy_snapshot.dart';
import 'observation_request.dart';
import 'stability_metadata.dart';

/// Outcome of a [PolicyLoop.run] invocation.
class PolicyTick {
  const PolicyTick({
    required this.reason,
    required this.durationMs,
    required this.extensionsBusy,
  });

  /// Why the loop terminated.
  final TerminatedBy reason;

  /// Wall-clock duration the loop ran, in ms.
  final int durationMs;

  /// Extensions still reporting busy at termination. Empty for `idle` and
  /// `quietFrame` terminations by construction.
  final List<ExtensionBusy> extensionsBusy;
}

/// Signature of the per-iteration extension busy-state poller.
///
/// Each entry's key is a extension namespace; isolation of throwing
/// `busyState()` calls (returning `BusyState.idle` and incrementing the
/// strike counter) is the caller's responsibility — typically wrapping
/// `ExtensionRegistry.busyStateAll`.
typedef BusyStatesPoller = Future<List<MapEntry<String, BusyState>>> Function();

/// Drives the stable-observation polling loop.
///
/// The loop polls cx6.4's [FrameworkBusySnapshot] and (via
/// [pollBusyStates]) every extension's [BusyState], folding both into the
/// active policy's termination predicate. The poller is expected to
/// isolate extension exceptions; thrown extensions must contribute a non-busy
/// entry so the loop is never aborted.
class PolicyLoop {
  PolicyLoop({
    required FrameworkBusySnapshot Function() snapshot,
    required BusyStatesPoller pollBusyStates,
    required int Function() semanticsHash,
    required int Function() routeHash,
    Stopwatch Function()? stopwatchFactory,
    Future<void> Function()? waitForFrame,
    int Function()? nowMs,
  }) : _snapshot = snapshot,
       _pollBusyStates = pollBusyStates,
       _semanticsHash = semanticsHash,
       _routeHash = routeHash,
       _stopwatchFactory = stopwatchFactory ?? (() => Stopwatch()..start()),
       _waitForFrame = waitForFrame ?? _defaultWaitForFrame,
       _nowMs = nowMs;

  final FrameworkBusySnapshot Function() _snapshot;
  final BusyStatesPoller _pollBusyStates;
  final int Function() _semanticsHash;
  final int Function() _routeHash;
  final Stopwatch Function() _stopwatchFactory;
  final Future<void> Function() _waitForFrame;
  final int Function()? _nowMs;

  static Future<void> _defaultWaitForFrame() {
    return SchedulerBinding.instance.endOfFrame;
  }

  /// Run the loop until the policy terminates and return the resulting
  /// [PolicyTick]. The loop yields between iterations via [_waitForFrame]
  /// (defaults to `SchedulerBinding.instance.endOfFrame`) so it never
  /// busy-waits.
  Future<PolicyTick> run(ObservationRequest req) async {
    final Stopwatch sw = _stopwatchFactory();
    final int initSem = _semanticsHash();
    final int initRoute = _routeHash();
    int quiet = 0;

    int elapsedMs() {
      if (_nowMs != null) return _nowMs();
      return sw.elapsedMilliseconds;
    }

    // Each policy must terminate eventually:
    // - actionRelative: budget bounds the loop.
    // - boundedStability: budget bounds the loop.
    // - quietFrame: bounded only by the idle streak; we still apply a
    //   defensive guard equal to kMaxBudgetMs so a permanently-busy app
    //   does not hang the harness. Hitting that guard is treated as
    //   `budget` termination.
    while (true) {
      final FrameworkBusySnapshot fw = _snapshot();
      final List<MapEntry<String, BusyState>> busy = await _pollBusyStates();
      final bool fwIdle = !fw.isAnyBusy;
      final bool extensionsIdle = busy.every(
        (MapEntry<String, BusyState> e) => !e.value.isBusy,
      );
      final List<ExtensionBusy> pBusy = <ExtensionBusy>[
        for (final MapEntry<String, BusyState> e in busy)
          if (e.value.isBusy)
            ExtensionBusy(
              e.key,
              reason: e.value.reason,
              estMs: e.value.estimatedDuration?.inMilliseconds,
            ),
      ];
      final int ms = elapsedMs();

      switch (req.policy) {
        case StabilityPolicy.actionRelative:
          if (_routeHash() != initRoute) {
            return PolicyTick(
              reason: TerminatedBy.routeChange,
              durationMs: ms,
              extensionsBusy: pBusy,
            );
          }
          if (_semanticsHash() != initSem) {
            return PolicyTick(
              reason: TerminatedBy.semanticsChange,
              durationMs: ms,
              extensionsBusy: pBusy,
            );
          }
          if (fwIdle && extensionsIdle) {
            return PolicyTick(
              reason: TerminatedBy.idle,
              durationMs: ms,
              extensionsBusy: const <ExtensionBusy>[],
            );
          }
          if (ms >= req.actionRelativeBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
            );
          }
          break;

        case StabilityPolicy.quietFrame:
          quiet = (fwIdle && extensionsIdle) ? quiet + 1 : 0;
          if (quiet >= req.quietFrameN) {
            return PolicyTick(
              reason: TerminatedBy.quietFrame,
              durationMs: ms,
              extensionsBusy: const <ExtensionBusy>[],
            );
          }
          if (ms >= kMaxBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
            );
          }
          break;

        case StabilityPolicy.boundedStability:
          quiet = (fwIdle && extensionsIdle) ? quiet + 1 : 0;
          if (quiet >= req.quietFrameN) {
            return PolicyTick(
              reason: TerminatedBy.quietFrame,
              durationMs: ms,
              extensionsBusy: const <ExtensionBusy>[],
            );
          }
          if (ms >= req.boundedStabilityBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
            );
          }
          break;
      }

      await _waitForFrame();
    }
  }
}
