import 'dart:async';

import 'package:leonard_flutter/src/contract/types.dart';
import 'package:leonard_flutter/src/observation/observation_request.dart';
import 'package:leonard_flutter/src/observation/policy_loop.dart';
import 'package:leonard_flutter/src/observation/stability_metadata.dart';
import 'package:leonard_flutter/src/stability/framework_busy_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted snapshot/busy/clock harness. Iteration N reads index N from
/// each script; the trailing element is sticky so policies that take
/// extra iterations still see a defined value.
class _Script {
  _Script({
    required this.frameworks,
    required this.busy,
    required this.elapsedMs,
    this.semanticsHashes,
    this.routeHashes,
  }) : _initialSem = semanticsHashes != null ? semanticsHashes.first : 0;

  final List<FrameworkBusySnapshot> frameworks;
  final List<List<MapEntry<String, BusyState>>> busy;
  final List<int> elapsedMs;
  final List<int>? semanticsHashes;
  final List<int>? routeHashes;
  final int _initialSem;

  int frameIndex = 0;
  int busyIndex = 0;
  int clockIndex = 0;
  int semIndex = 0;
  int routeIndex = 0;
  int waitCalls = 0;

  T _read<T>(List<T> xs, int i) => xs[i < xs.length ? i : xs.length - 1];

  FrameworkBusySnapshot snapshot() {
    final FrameworkBusySnapshot v = _read(frameworks, frameIndex);
    frameIndex++;
    return v;
  }

  Future<List<MapEntry<String, BusyState>>> pollBusy() async {
    final List<MapEntry<String, BusyState>> v = _read(busy, busyIndex);
    busyIndex++;
    return v;
  }

  int now() {
    final int v = _read(elapsedMs, clockIndex);
    clockIndex++;
    return v;
  }

  int semHash() {
    if (semanticsHashes == null) return _initialSem;
    final int v = _read(semanticsHashes!, semIndex);
    semIndex++;
    return v;
  }

  int routeHash() {
    if (routeHashes == null) return 0;
    final int v = _read(routeHashes!, routeIndex);
    routeIndex++;
    return v;
  }

  Future<void> waitForFrame() async {
    waitCalls++;
  }
}

FrameworkBusySnapshot _busyFw() => const FrameworkBusySnapshot(
  transientCallbacks: 1,
  persistentCallbacks: 0,
  pendingMicrotasks: false,
  lastFrameCommitTimestamp: null,
  recentSkippedFrames: 0,
  recentFrameCommits: <Duration>[],
);

const FrameworkBusySnapshot _idleFw = FrameworkBusySnapshot.zero;

/// A [Timer] that never fires and records whether it was cancelled.
class _RecordingTimer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

/// A [Timer] that fires its callback on the next microtask, standing in for
/// the budget deadline when frames have stopped arriving.
class _ImmediateTimer implements Timer {
  _ImmediateTimer(void Function() callback) {
    scheduleMicrotask(() {
      if (_active) callback();
      _active = false;
    });
  }

  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

List<MapEntry<String, BusyState>> _busyExtensions(
  List<({String ns, bool busy, String? reason, int? estMs})> spec,
) {
  return <MapEntry<String, BusyState>>[
    for (final p in spec)
      MapEntry<String, BusyState>(
        p.ns,
        BusyState(
          isBusy: p.busy,
          reason: p.reason,
          estimatedDuration: p.estMs == null
              ? null
              : Duration(milliseconds: p.estMs!),
        ),
      ),
  ];
}

void main() {
  group('action-relative termination conditions', () {
    test('idle: framework + all extensions idle on first poll', () async {
      // PolicyLoop reads semHash and routeHash twice per iteration in the
      // action-relative branch (initial + check). Provide >=2 entries so
      // the script does not run dry on the second read.
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_idleFw],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: false, reason: null, estMs: null),
            ],
          ),
        ],
        elapsedMs: <int>[10],
        semanticsHashes: <int>[1, 1],
        routeHashes: <int>[1, 1],
      );

      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: s.semHash,
        routeHash: s.routeHash,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.idle);
      expect(tick.settled, isTrue);
      expect(tick.extensionsBusy, isEmpty);
    });

    test(
      'idle: persistent-callback baseline alone does not block (lenny-ndnp)',
      () async {
        // The real steady state of any running app: a persistent-callback
        // baseline with no transient work and no microtasks. This must read as
        // idle, so action-relative terminates `idle` instead of riding the full
        // budget. Before the fix, persistentCallbacks made isAnyBusy permanently
        // true and this same snapshot forced a budget timeout on every turn.
        const FrameworkBusySnapshot baselineFw = FrameworkBusySnapshot(
          transientCallbacks: 0,
          persistentCallbacks: 2,
          pendingMicrotasks: false,
          lastFrameCommitTimestamp: null,
          recentSkippedFrames: 0,
          recentFrameCommits: <Duration>[],
        );
        final _Script s = _Script(
          frameworks: <FrameworkBusySnapshot>[baselineFw],
          busy: <List<MapEntry<String, BusyState>>>[
            _busyExtensions(
              <({String ns, bool busy, String? reason, int? estMs})>[
                (ns: 'p1', busy: false, reason: null, estMs: null),
              ],
            ),
          ],
          elapsedMs: <int>[10],
          semanticsHashes: <int>[1, 1],
          routeHashes: <int>[1, 1],
        );
        final PolicyLoop loop = PolicyLoop(
          snapshot: s.snapshot,
          pollBusyStates: s.pollBusy,
          semanticsHash: s.semHash,
          routeHash: s.routeHash,
          waitForFrame: s.waitForFrame,
          nowMs: s.now,
        );
        final PolicyTick tick = await loop.run(const ObservationRequest());
        expect(tick.reason, TerminatedBy.idle);
      },
    );

    // lenny-r1k2x: a route or semantics change is the first sign the action
    // took effect, not a settled screen. On an iPad a push flipped the route
    // hash on its first frame while the transition was still animating, and
    // the observation captured two empty containers. A change now starts a
    // settle that ends on a quiet-frame streak or the settle budget.
    PolicyLoop loopFor(_Script s) => PolicyLoop(
      snapshot: s.snapshot,
      pollBusyStates: s.pollBusy,
      semanticsHash: s.semHash,
      routeHash: s.routeHash,
      waitForFrame: s.waitForFrame,
      nowMs: s.now,
    );

    List<MapEntry<String, BusyState>> idleExtension() =>
        _busyExtensions(<({String ns, bool busy, String? reason, int? estMs})>[
          (ns: 'p1', busy: false, reason: null, estMs: null),
        ]);

    test(
      'routeChange: a route flip mid-transition settles on quiet frames',
      () async {
        final _Script s = _Script(
          // The transition animates for three frames, then two quiet ones.
          frameworks: <FrameworkBusySnapshot>[
            _busyFw(),
            _busyFw(),
            _busyFw(),
            _idleFw,
            _idleFw,
          ],
          busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
          elapsedMs: <int>[20, 60, 120, 180, 240],
          semanticsHashes: <int>[1],
          routeHashes: <int>[1, 2], // initial, then changed for good
        );
        final PolicyTick tick = await loopFor(
          s,
        ).run(const ObservationRequest());
        expect(tick.reason, TerminatedBy.routeChange);
        expect(tick.settled, isTrue);
        expect(tick.durationMs, 240);
        expect(tick.extensionsBusy, isEmpty);
      },
    );

    test('routeChange: a settle that never goes quiet ends unsettled at the '
        'settle budget, not the 800 ms action budget', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 700, 900, 1400, 1500],
        semanticsHashes: <int>[1],
        routeHashes: <int>[1, 2],
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.routeChange);
      expect(tick.settled, isFalse);
      expect(tick.durationMs, kDefaultActionRelativeSettleBudgetMs);
    });

    test('semanticsChange: a semantics flip settles on quiet frames', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _idleFw, _idleFw],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 40, 60],
        semanticsHashes: <int>[10, 11],
        routeHashes: <int>[1, 1],
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.semanticsChange);
      expect(tick.settled, isTrue);
      expect(tick.durationMs, 60);
    });

    test(
      'a route change during a semantics settle reports routeChange',
      () async {
        final _Script s = _Script(
          frameworks: <FrameworkBusySnapshot>[
            _busyFw(),
            _busyFw(),
            _idleFw,
            _idleFw,
          ],
          busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
          elapsedMs: <int>[20, 40, 60, 80],
          semanticsHashes: <int>[10, 11],
          routeHashes: <int>[1, 1, 2],
        );
        final PolicyTick tick = await loopFor(
          s,
        ).run(const ObservationRequest());
        expect(tick.reason, TerminatedBy.routeChange);
        expect(tick.settled, isTrue);
      },
    );

    test('a semantics-only change that never goes quiet ends unsettled at the '
        'action budget, not the settle budget', () async {
      // A carousel or shimmer moves node rects every frame, so the
      // semantics hash changes every frame; that must cost no more than a
      // no-change wait.
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 400, 800, 1500],
        semanticsHashes: <int>[10, 11, 12, 13, 14],
        routeHashes: <int>[1],
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.semanticsChange);
      expect(tick.settled, isFalse);
      expect(tick.durationMs, kDefaultActionRelativeBudgetMs);
    });

    test('a route change during a semantics settle extends it to the settle '
        'budget', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 300, 700, 900, 1500],
        semanticsHashes: <int>[10, 11],
        routeHashes: <int>[1, 1, 1, 2],
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.routeChange);
      expect(tick.settled, isFalse);
      expect(tick.durationMs, kDefaultActionRelativeSettleBudgetMs);
    });

    test('a busy frame inside a settle resets the quiet streak', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[
          _idleFw,
          _busyFw(),
          _idleFw,
          _idleFw,
        ],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 40, 60, 80],
        semanticsHashes: <int>[1],
        routeHashes: <int>[1, 2],
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.settled, isTrue);
      expect(tick.durationMs, 80);
    });

    test(
      'an extension busy while the framework is idle keeps the settle going',
      () async {
        List<MapEntry<String, BusyState>> busyExtension() => _busyExtensions(
          <({String ns, bool busy, String? reason, int? estMs})>[
            (ns: 'p1', busy: true, reason: 'navigating', estMs: null),
          ],
        );
        final _Script s = _Script(
          frameworks: <FrameworkBusySnapshot>[_idleFw],
          busy: <List<MapEntry<String, BusyState>>>[
            busyExtension(),
            busyExtension(),
            idleExtension(),
            idleExtension(),
          ],
          elapsedMs: <int>[20, 40, 60, 80],
          semanticsHashes: <int>[1],
          routeHashes: <int>[1, 2],
        );
        final PolicyTick tick = await loopFor(
          s,
        ).run(const ObservationRequest());
        expect(tick.reason, TerminatedBy.routeChange);
        expect(tick.settled, isTrue);
        expect(tick.durationMs, 80);
      },
    );

    test('a change that reverts during the settle still settles and reports '
        'the change that started it', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _idleFw, _idleFw],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 40, 60],
        semanticsHashes: <int>[1],
        routeHashes: <int>[1, 2, 1], // changed, then back
      );
      final PolicyTick tick = await loopFor(s).run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.routeChange);
      expect(tick.settled, isTrue);
      expect(tick.durationMs, 60);
    });

    test(
      'the frame that shows the change counts as the first quiet frame',
      () async {
        _Script quietChange() => _Script(
          frameworks: <FrameworkBusySnapshot>[_idleFw],
          busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
          elapsedMs: <int>[20, 40],
          semanticsHashes: <int>[1],
          routeHashes: <int>[1, 2],
        );
        final PolicyTick one = await loopFor(
          quietChange(),
        ).run(const ObservationRequest(quietFrameN: 1));
        expect(one.reason, TerminatedBy.routeChange);
        expect(one.settled, isTrue);
        expect(one.durationMs, 20);

        final PolicyTick two = await loopFor(
          quietChange(),
        ).run(const ObservationRequest());
        expect(two.settled, isTrue);
        expect(two.durationMs, 40);
      },
    );

    test('the deadline timer is cancelled when the frame wins', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _idleFw],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 40],
        semanticsHashes: <int>[1],
        routeHashes: <int>[1],
      );
      final List<_RecordingTimer> timers = <_RecordingTimer>[];
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: s.semHash,
        routeHash: s.routeHash,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
        createTimer: (Duration _, void Function() _) {
          final _RecordingTimer t = _RecordingTimer();
          timers.add(t);
          return t;
        },
      );
      final PolicyTick tick = await loop.run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.idle);
      expect(timers, hasLength(1));
      expect(timers.single.cancelled, isTrue);
    });

    test(
      'frames that stop arriving still end the loop at the budget, unsettled',
      () async {
        // endOfFrame never completes while frames are off (the app hidden,
        // paused or detached, e.g. after opening an external URL); the
        // budget deadline must end the wait instead.
        final _Script s = _Script(
          frameworks: <FrameworkBusySnapshot>[_busyFw()],
          busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
          elapsedMs: <int>[20, 400, 800],
          semanticsHashes: <int>[1],
          routeHashes: <int>[1],
        );
        int timers = 0;
        final PolicyLoop loop = PolicyLoop(
          snapshot: s.snapshot,
          pollBusyStates: s.pollBusy,
          semanticsHash: s.semHash,
          routeHash: s.routeHash,
          waitForFrame: () => Completer<void>().future,
          nowMs: s.now,
          createTimer: (Duration _, void Function() callback) {
            timers++;
            return _ImmediateTimer(callback);
          },
        );
        final PolicyTick tick = await loop
            .run(const ObservationRequest())
            .timeout(const Duration(seconds: 5));
        expect(tick.reason, TerminatedBy.budget);
        expect(tick.settled, isFalse);
        expect(tick.durationMs, 800);
        expect(timers, 2);
      },
    );

    test('a settle budget below the action budget is raised to it', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[idleExtension()],
        elapsedMs: <int>[20, 500, 800],
        semanticsHashes: <int>[1],
        routeHashes: <int>[1, 2],
      );
      final PolicyTick tick = await loopFor(
        s,
      ).run(const ObservationRequest(actionRelativeSettleBudgetMs: 100));
      expect(tick.reason, TerminatedBy.routeChange);
      expect(tick.settled, isFalse);
      expect(tick.durationMs, 800);
    });

    test('budget: never idle, hits 800ms cap', () async {
      // Three iterations; on the third the elapsed clock crosses 800.
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _busyFw(), _busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: true, reason: 'loading', estMs: 200),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: true, reason: 'loading', estMs: 200),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: true, reason: 'loading', estMs: 200),
            ],
          ),
        ],
        elapsedMs: <int>[100, 500, 900],
        semanticsHashes: <int>[1, 1, 1, 1, 1, 1],
        routeHashes: <int>[1, 1, 1, 1, 1, 1],
      );
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: s.semHash,
        routeHash: s.routeHash,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(const ObservationRequest());
      expect(tick.reason, TerminatedBy.budget);
      expect(tick.durationMs, 900);
      expect(tick.settled, isFalse);
      expect(tick.extensionsBusy, hasLength(1));
      expect(tick.extensionsBusy.first.namespace, 'p1');
      expect(tick.extensionsBusy.first.reason, 'loading');
      expect(tick.extensionsBusy.first.estMs, 200);
    });
  });

  group('quiet-frame N=2', () {
    test('terminates after 2 consecutive idle frames', () async {
      // Frame 1: busy. Frame 2: idle (quiet=1). Frame 3: idle (quiet=2 -> end).
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _idleFw, _idleFw],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: true, reason: null, estMs: null),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: false, reason: null, estMs: null),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: false, reason: null, estMs: null),
            ],
          ),
        ],
        elapsedMs: <int>[16, 32, 48],
      );
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: () => 0,
        routeHash: () => 0,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(
        const ObservationRequest(policy: StabilityPolicy.quietFrame),
      );
      expect(tick.reason, TerminatedBy.quietFrame);
      expect(tick.extensionsBusy, isEmpty);
      // Two yields between three iterations.
      expect(s.waitCalls, 2);
    });

    test('busy frame breaks the streak; counter resets', () async {
      // N=3. idle(q=1), idle(q=2), BUSY(q=0), idle(q=1), idle(q=2),
      // idle(q=3 -> terminate). 6 iterations.
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[
          _idleFw,
          _idleFw,
          _busyFw(),
          _idleFw,
          _idleFw,
          _idleFw,
        ],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
        ],
        elapsedMs: <int>[16, 32, 48, 64, 80, 96],
      );
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: () => 0,
        routeHash: () => 0,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(
        const ObservationRequest(
          policy: StabilityPolicy.quietFrame,
          quietFrameN: 3,
        ),
      );
      expect(tick.reason, TerminatedBy.quietFrame);
      expect(s.frameIndex, 6);
    });
  });

  group('bounded-stability', () {
    test('tags `budget` and reports extensions_busy on timeout', () async {
      // Always busy. After three iterations elapsed ms crosses 1500.
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw(), _busyFw(), _busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'q', busy: true, reason: 'animating', estMs: 500),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'q', busy: true, reason: 'animating', estMs: 500),
            ],
          ),
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'q', busy: true, reason: 'animating', estMs: 500),
            ],
          ),
        ],
        elapsedMs: <int>[100, 800, 1600],
      );
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: () => 0,
        routeHash: () => 0,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(
        const ObservationRequest(policy: StabilityPolicy.boundedStability),
      );
      expect(tick.reason, TerminatedBy.budget);
      expect(tick.durationMs, 1600);
      expect(tick.extensionsBusy.single.namespace, 'q');
      expect(tick.extensionsBusy.single.reason, 'animating');
      expect(tick.extensionsBusy.single.estMs, 500);
    });

    test('terminates on quietFrame condition before budget elapses', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_idleFw, _idleFw],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
          _busyExtensions(
            const <({String ns, bool busy, String? reason, int? estMs})>[],
          ),
        ],
        elapsedMs: <int>[16, 32],
      );
      final PolicyLoop loop = PolicyLoop(
        snapshot: s.snapshot,
        pollBusyStates: s.pollBusy,
        semanticsHash: () => 0,
        routeHash: () => 0,
        waitForFrame: s.waitForFrame,
        nowMs: s.now,
      );
      final PolicyTick tick = await loop.run(
        const ObservationRequest(
          policy: StabilityPolicy.boundedStability,
          quietFrameN: 2,
        ),
      );
      expect(tick.reason, TerminatedBy.quietFrame);
      expect(tick.durationMs, 32);
    });
  });
}
