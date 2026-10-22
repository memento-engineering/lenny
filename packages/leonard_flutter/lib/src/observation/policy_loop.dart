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
    required this.settled,
  });

  /// Why the loop terminated. For an action-relative settle this is the
  /// change that started it ([TerminatedBy.routeChange] or
  /// [TerminatedBy.semanticsChange]), whether or not it settled.
  final TerminatedBy reason;

  /// Whether the app was quiet when the loop ended: the framework and every
  /// extension idle (for a settle or the quiet-frame policies, for the
  /// required streak of frames). False when a budget ran out first, so the
  /// observation may show a screen mid-animation.
  final bool settled;

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
/// The loop polls the [FrameworkBusySnapshot] and (via
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
    TerminatedBy? trigger;

    int elapsedMs() {
      if (_nowMs != null) return _nowMs();
      return sw.elapsedMilliseconds;
    }

    // Each policy must terminate eventually:
    // - actionRelative: budget bounds the loop, or the settle budget once
    //   a change has started a settle.
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
          // A route or semantics change is the first sign the action took
          // effect, not a settled screen: a push flips the route on its
          // first frame while the transition still animates (lenny-r1k2x).
          // So a change starts a settle that ends on a quiet-frame streak,
          // bounded by the longer settle budget.
          final TerminatedBy? change = _routeHash() != initRoute
              ? TerminatedBy.routeChange
              : (_semanticsHash() != initSem
                    ? TerminatedBy.semanticsChange
                    : null);
          if (change != null &&
              (trigger == null || change == TerminatedBy.routeChange)) {
            trigger = change;
          }
          final TerminatedBy? settling = trigger;
          if (settling != null) {
            quiet = (fwIdle && extensionsIdle) ? quiet + 1 : 0;
            if (quiet >= req.quietFrameN) {
              return PolicyTick(
                reason: settling,
                durationMs: ms,
                extensionsBusy: const <ExtensionBusy>[],
                settled: true,
              );
            }
            final int settleBudget =
                req.actionRelativeSettleBudgetMs > req.actionRelativeBudgetMs
                ? req.actionRelativeSettleBudgetMs
                : req.actionRelativeBudgetMs;
            if (ms >= settleBudget) {
              return PolicyTick(
                reason: settling,
                durationMs: ms,
                extensionsBusy: pBusy,
                settled: false,
              );
            }
            break;
          }
          if (fwIdle && extensionsIdle) {
            return PolicyTick(
              reason: TerminatedBy.idle,
              durationMs: ms,
              extensionsBusy: const <ExtensionBusy>[],
              settled: true,
            );
          }
          if (ms >= req.actionRelativeBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
              settled: false,
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
              settled: true,
            );
          }
          if (ms >= kMaxBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
              settled: false,
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
              settled: true,
            );
          }
          if (ms >= req.boundedStabilityBudgetMs) {
            return PolicyTick(
              reason: TerminatedBy.budget,
              durationMs: ms,
              extensionsBusy: pBusy,
              settled: false,
            );
          }
          break;
      }

      await _waitForFrame();
    }
  }
}
