/// A reusable, scriptable [NativeBackend] test double — the native analogue of
/// `FakeTmuxExecutor`. Shipped in `lib/` (not `test/`) so downstream packages
/// and the host/extension tests can drive the seam without a device.
///
/// It records every call, lets the test push snapshots (including error events)
/// onto the [watch] stream, exposes a settable one-shot [snapshot] payload, and
/// resolves selectors per-tier (a11y-id / label / xpath / rect-center,
/// including the anonymous-label -> positional-xpath case). A secure field is
/// scripted via [secureFieldValue]: its [enterText] returns
/// `(readback: <masked bullets>, masked: true)`.
library;

import 'dart:async';

import 'native_backend.dart';
import 'native_snapshot.dart';

/// One recorded backend call, for assertions.
class FakeNativeCall {
  /// Records the verb [name] and an optional [detail] payload.
  FakeNativeCall(this.name, [this.detail]);

  /// The backend verb, e.g. `tap`/`enterText`/`press`/`swipe`/`resolve`.
  final String name;

  /// Verb-specific detail (the resolved [NativeTarget], the press key, …).
  final Object? detail;

  @override
  String toString() => 'FakeNativeCall($name, $detail)';
}

/// A scriptable [NativeBackend] for unit tests.
class FakeNativeBackend implements NativeBackend {
  /// Seeds the fake with an initial [snapshotPayload] and the [platform].
  FakeNativeBackend({NativeSnapshot? snapshotPayload, this.platform = 'ios'})
    : _snapshot =
          snapshotPayload ??
          const NativeSnapshot(platform: 'ios', nodes: <NativeNode>[]);

  /// The platform reported by snapshots emitted from this fake.
  final String platform;

  /// Ordered log of every backend call the fake received.
  final List<FakeNativeCall> calls = <FakeNativeCall>[];

  final StreamController<NativeSnapshot> _watch =
      StreamController<NativeSnapshot>.broadcast();
  NativeSnapshot _snapshot;

  /// When set, [enterText] treats the field as secure: it returns the masked
  /// readback below with `masked: true` regardless of the typed text. When
  /// null, [enterText] echoes the typed text with `masked: false`.
  String? secureFieldValue;

  /// The masked readback a secure field reports (bullets, ≠ plaintext).
  String maskedReadback = '••••••••';

  /// Optional scripted resolver. When set, it fully decides resolution; when
  /// null, the fake uses its built-in per-tier chain ([_defaultResolve]).
  Future<NativeTarget?> Function(
    NativeSelector selector,
    NativeSnapshot? cached,
  )?
  resolver;

  /// Replace the one-shot [snapshot] payload (e.g. to reflect a post-tap
  /// change). Does NOT push onto the [watch] stream.
  set snapshotPayload(NativeSnapshot value) => _snapshot = value;

  /// Push a fresh snapshot onto the [watch] stream (a poll tick).
  void pushSnapshot(NativeSnapshot snap) {
    _snapshot = snap;
    _watch.add(snap);
  }

  /// Push a transient error event onto the [watch] stream — the extension must
  /// swallow it and keep the last-good snapshot.
  void pushError(Object error) => _watch.addError(error);

  @override
  Future<void> connect() async {
    calls.add(FakeNativeCall('connect'));
  }

  @override
  Stream<NativeSnapshot> watch() => _watch.stream;

  @override
  Future<NativeSnapshot> snapshot() async {
    calls.add(FakeNativeCall('snapshot'));
    return _snapshot;
  }

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) async {
    final NativeTarget? t = resolver != null
        ? await resolver!(selector, cached)
        : _defaultResolve(selector, cached);
    calls.add(FakeNativeCall('resolve', t));
    return t;
  }

  /// Built-in per-tier resolver walking a11y-id -> label -> xpath ->
  /// rect-center. The label tier resolves an anonymous cached node (no a11yId)
  /// through a synthesized positional xpath, recording `via:'label'`.
  NativeTarget? _defaultResolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) {
    if (selector.a11yId != null) {
      return NativeTarget(elementId: 'el-${selector.a11yId}', via: 'a11y-id');
    }
    if (selector.label != null) {
      final NativeNode? node = _matchLabel(cached, selector.label!);
      if (node != null) {
        // Resolve the matched node deterministically: a11yId, else its xpath,
        // else a synthesized positional xpath. All record via:'label'.
        if (node.a11yId != null && node.a11yId!.isNotEmpty) {
          return NativeTarget(elementId: 'el-${node.a11yId}', via: 'label');
        }
        final String xpath = node.xpath ?? '(//*)[${node.id}]';
        return NativeTarget(elementId: 'el-$xpath', via: 'label');
      }
    }
    if (selector.xpath != null) {
      return NativeTarget(elementId: 'el-${selector.xpath}', via: 'xpath');
    }
    if (selector.rect != null && selector.rect!.length == 4) {
      final List<int> r = selector.rect!;
      return NativeTarget(
        point: (x: ((r[0] + r[2]) / 2).round(), y: ((r[1] + r[3]) / 2).round()),
        via: 'rect-center',
      );
    }
    return null;
  }

  NativeNode? _matchLabel(NativeSnapshot? cached, String label) {
    if (cached == null) return null;
    for (final NativeNode n in cached.nodes) {
      if (n.label == label) return n;
    }
    return null;
  }

  @override
  Future<void> tap(NativeTarget target) async {
    calls.add(FakeNativeCall('tap', target));
  }

  @override
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  ) async {
    calls.add(FakeNativeCall('enterText', (target: target, text: text)));
    if (secureFieldValue != null) {
      return (readback: maskedReadback, masked: true);
    }
    return (readback: text, masked: false);
  }

  @override
  Future<void> press(String key) async {
    calls.add(FakeNativeCall('press', key));
    const Set<String> recognized = <String>{
      'enter',
      'return',
      'done',
      'consent_accept',
      'alert_dismiss',
      'back',
    };
    if (!recognized.contains(key)) {
      throw NativeException('unknown press key: $key');
    }
  }

  @override
  Future<void> swipe(NativeSwipe gesture) async {
    calls.add(FakeNativeCall('swipe', gesture));
  }

  @override
  Future<void> close() async {
    calls.add(FakeNativeCall('close'));
    await _watch.close();
  }
}
