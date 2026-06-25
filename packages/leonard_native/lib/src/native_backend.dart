/// The `NativeBackend` seam — the I/O boundary that keeps `buildPerception()`
/// synchronous (ADR-0006). ALL device latency (WebDriver round-trips, a11y-tree
/// polling) lives behind it; the extension never touches the device directly.
///
/// `AppiumBackend` is the first concrete impl; `FakeNativeBackend` is the test
/// impl; a later `UiAutomator2Backend` is purely additive.
library;

import 'package:meta/meta.dart';

import 'native_snapshot.dart';

/// Resolved target of a native action — what the selector chain produced.
///
/// [elementId] is the backend's W3C element handle when one resolved
/// (a11y-id / label / xpath tier); when only rect-center resolved, [elementId]
/// is null and the backend taps [point].
@immutable
class NativeTarget {
  /// Records the resolved [elementId] and/or [point], and which tier [via] won.
  const NativeTarget({this.elementId, this.point, required this.via});

  /// W3C `element-6066-...` handle, or null (rect-center).
  final String? elementId;

  /// Rect-center fallback coordinate, or null.
  final ({int x, int y})? point;

  /// `a11y-id` | `label` | `xpath` | `rect-center`.
  final String via;
}

/// A selector spec carrying the raw tool args for the resolution chain.
@immutable
class NativeSelector {
  /// Records the per-tier selector args.
  const NativeSelector({this.a11yId, this.label, this.xpath, this.rect});

  /// Tier 1: a11y identifier.
  final String? a11yId;

  /// Tier 2: visible label (matched against `node.label`).
  final String? label;

  /// Tier 3: XPath (load-bearing for anonymous Auth0 fields).
  final String? xpath;

  /// Tier 4: `[l,t,r,b]`; tap at center `((l+r)/2, (t+b)/2)`.
  final List<int>? rect;
}

/// A swipe gesture spec.
@immutable
class NativeSwipe {
  /// Records the gesture endpoints and optional [durationMs].
  const NativeSwipe({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    this.durationMs = 300,
  });

  /// Gesture start x.
  final int fromX;

  /// Gesture start y.
  final int fromY;

  /// Gesture end x.
  final int toX;

  /// Gesture end y.
  final int toY;

  /// Gesture duration in milliseconds.
  final int durationMs;
}

/// Thrown by a backend for an expected device/transport failure. Tools catch
/// this and return `ToolResult(ok:false, error:e.message)` — they never
/// rethrow.
class NativeException implements Exception {
  /// Wraps a human-readable [message].
  NativeException(this.message);

  /// The failure message surfaced to the agent.
  final String message;

  @override
  String toString() => 'NativeException: $message';
}

/// The seam the watcher drives and the tools act through. `AppiumBackend` is
/// the first impl; `FakeNativeBackend` is the test impl. Per-platform behavior
/// (iOS ASWebAuthenticationSession consent, iOS Done vs Android back keyboard
/// dismiss, iOS-vs-Android readback attribute) lives INSIDE the impl, never in
/// the extension/tools.
///
/// Recognized [press] keys are platform-specific and documented on the impl,
/// NOT enforced by an allowlist on the tool. iOS recognizes
/// `enter`/`return`/`done`/`consent_accept`; Android additively recognizes
/// `back`. An unrecognized key surfaces as a [NativeException] from the impl.
abstract class NativeBackend {
  /// Open the device session against an ALREADY-RUNNING Appium server and an
  /// ALREADY-BOOTED simulator. The backend does NOT spawn Appium or boot the
  /// sim (that lifecycle is m4). Idempotent.
  Future<void> connect();

  /// Out-of-band poll loop: emits a fresh [NativeSnapshot] each tick (reading
  /// `/source` for Appium, parsing the XCUITest XML). This is the watcher's
  /// source — the snapshot IS the event payload.
  Stream<NativeSnapshot> watch();

  /// One-shot capture for seeding the cache in `initialize()` and for the
  /// post-action refresh tools call (the poll loop may not have ticked since
  /// the tap/text). Same payload shape as a [watch] event.
  Future<NativeSnapshot> snapshot();

  /// Resolve [selector] against the device into a [NativeTarget], walking the
  /// chain a11y-id -> label -> xpath -> rect-center. Returns null when nothing
  /// resolves. [cached] is the current snapshot (for label-match and
  /// rect-center synthesis) — pass it so resolution can fall back to a node
  /// rect without an extra round-trip.
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  );

  /// Tap a resolved [target] (element click, or a point tap for rect-center).
  Future<void> tap(NativeTarget target);

  /// Clear + type [text] into [target], then dismiss the keyboard per-platform
  /// (iOS Done / Android back) INSIDE this method. Returns `(readback,
  /// masked)`: `readback` is the `GET .../attribute/value` result; `masked` is
  /// derived from the ELEMENT TYPE (true iff the element is a SecureTextField),
  /// NOT from `readback != text`.
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  );

  /// A logical key press. iOS: `enter`|`return`|`done`|`consent_accept`|
  /// `alert_dismiss` — `consent_accept` issues
  /// `POST /session/{id}/alert/accept` (the iOS-only ASWebAuthenticationSession
  /// consent path); `alert_dismiss` issues `POST /session/{id}/alert/dismiss`
  /// (the iOS-only "Save Password?" / system-alert cancel path, parallel to
  /// `consent_accept`). Android additive: `back`. An unrecognized key throws
  /// [NativeException]; an alert-endpoint key issued when no alert is open
  /// surfaces the W3C "no alert open" error as a [NativeException].
  Future<void> press(String key);

  /// Swipe gesture (W3C actions / `mobile: swipe`).
  Future<void> swipe(NativeSwipe gesture);

  /// Tear down the device session and any HTTP client. Does NOT stop Appium or
  /// shut down the sim.
  Future<void> close();
}
