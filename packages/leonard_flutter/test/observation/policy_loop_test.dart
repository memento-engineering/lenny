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
    test('idle: framework + all plugins idle on first poll', () async {
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
      expect(tick.extensionsBusy, isEmpty);
    });

    test('routeChange: route hash flips before idle', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: false, reason: null, estMs: null),
            ],
          ),
        ],
        elapsedMs: <int>[20],
        semanticsHashes: <int>[1, 1],
        routeHashes: <int>[1, 2], // initial then changed
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
      expect(tick.reason, TerminatedBy.routeChange);
    });

    test('semanticsChange: semantics hash flips before idle', () async {
      final _Script s = _Script(
        frameworks: <FrameworkBusySnapshot>[_busyFw()],
        busy: <List<MapEntry<String, BusyState>>>[
          _busyExtensions(
            <({String ns, bool busy, String? reason, int? estMs})>[
              (ns: 'p1', busy: false, reason: null, estMs: null),
            ],
          ),
        ],
        elapsedMs: <int>[20],
        semanticsHashes: <int>[10, 11],
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
      expect(tick.reason, TerminatedBy.semanticsChange);
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
