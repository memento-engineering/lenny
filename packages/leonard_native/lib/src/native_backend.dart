/// The `NativeBackend` seam — the I/O boundary that keeps `buildPerception()`
/// synchronous (the pull-free build invariant). ALL device latency (WebDriver
/// round-trips, a11y-tree polling) lives behind it; the extension never
/// touches the device directly.
///
/// `XcuiTestBackend` (iOS) and `UiAutomator2Backend` (Android) are the
/// concrete impls; `FakeNativeBackend` is the test impl.
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
  /// Backend recovery code for a resolved field hidden by a platform overlay.
  ///
  /// [NativeBackend.enterText] DETECTS the obstruction and throws with this
  /// code. It does NOT recover: at that seam it holds an already-resolved
  /// [NativeTarget] and cannot re-resolve the handle that dismissal
  /// invalidates.
  ///
  /// Recovery is automatic **only through the Leonard tool surface** — the
  /// `enter_text` tool owns it, being the layer that holds the selector. A
  /// consumer driving a [NativeBackend] DIRECTLY must implement it, and this is
  /// the whole recipe:
  ///
  /// ```dart
  /// ({String readback, bool masked}) result;
  /// try {
  ///   result = await backend.enterText(target, text);
  /// } on NativeException catch (e) {
  ///   if (e.code != NativeException.fieldObscuredCode) rethrow;
  ///   try {
  ///     // Positively gated inside the backend: this THROWS rather than
  ///     // pressing back when nothing is actually obstructing, so it cannot
  ///     // navigate a Chrome Custom Tab away.
  ///     await backend.press('dismiss_overlay');
  ///   } on NativeException {
  ///     // That gate makes a FAILED dismissal an expected race — the overlay
  ///     // can clear on its own between the write failing and this call — so
  ///     // keep `e` as the reported cause. Letting the dismissal failure
  ///     // replace it reports "no dismissible platform overlay is present",
  ///     // which reads as broken recovery rather than as the real obstruction.
  ///     throw e;
  ///   }
  ///   // Dismissal INVALIDATES the handle — re-resolve, never reuse `target`.
  ///   final NativeTarget? fresh = await backend.resolve(selector, cached);
  ///   if (fresh == null) {
  ///     throw NativeException(
  ///       'element disappeared after obstruction dismissal',
  ///       code: NativeException.elementGoneAfterDismissalCode,
  ///     );
  ///   }
  ///   result = await backend.enterText(fresh, text);
  /// }
  /// ```
  ///
  /// This mirrors `_EnterTextTool` exactly, including which error survives a
  /// failed dismissal — the two must not diverge, because the recipe is the
  /// migration path for consumers who cannot use the tool.
  ///
  /// Branch on this code, never on [message] — the message is model-facing
  /// prose and may be reworded.
  static const String fieldObscuredCode = 'field obscured';

  /// Recovery code for "the obstruction cleared, but the element is gone".
  ///
  /// Carried by the [fieldObscuredCode] recipe above when the post-dismissal
  /// re-resolve finds nothing. It exists so that outcome is distinguishable
  /// from a generic resolve failure WITHOUT string-matching [message] — the
  /// habit [code] was introduced to retire.
  ///
  /// A caller seeing this knows dismissal SUCCEEDED and the screen then moved
  /// on (a navigation, a re-render), so retrying the write against a fresh
  /// lookup of the same selector is unlikely to help; re-observe instead of
  /// looping.
  static const String elementGoneAfterDismissalCode =
      'element gone after dismissal';

  /// Wraps a human-readable [message], optionally tagged with a W3C or
  /// backend-defined recovery [code].
  NativeException(this.message, {this.code});

  /// The failure message surfaced to the agent.
  ///
  /// This string is model-facing — a tool returns it as
  /// `ToolResult.error` — so treat it as part of the contract. When [code] is
  /// set the message still carries it as a prefix; that redundancy is
  /// deliberate, so adding [code] did not change what the agent reads.
  final String message;

  /// A W3C WebDriver error code or a documented backend recovery code.
  ///
  /// Callers branch on this rather than pattern-matching [message], so an
  /// adaptive path cannot be silently disabled by a reworded message.
  final String? code;

  @override
  String toString() => 'NativeException: $message';
}

/// The seam the watcher drives and the tools act through. `XcuiTestBackend` is
/// the first impl; `FakeNativeBackend` is the test impl. Per-platform behavior
/// (iOS ASWebAuthenticationSession consent, iOS Done vs Android back keyboard
/// dismiss, iOS-vs-Android readback attribute) lives INSIDE the impl, never in
/// the extension/tools.
///
/// Recognized [press] keys are platform-specific and documented on the impl,
/// NOT enforced by an allowlist on the tool. The shared iOS/Android set is
/// `enter`/`return`/`done`; the iOS-only set is
/// `consent_accept`/`alert_dismiss`; the Android-only set is `back` plus the
/// internal `dismiss_overlay` recovery action. An unrecognized key surfaces as
/// a [NativeException] from the impl.
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
  ///
  /// THIS ALREADY RETRIES INTERNALLY, and callers must size their own retry
  /// budgets against that. The cost is **per POPULATED tier**, not per call:
  /// each tier is skipped when its selector field is null, and each tier that
  /// does run an element find carries its own ~10 s retry window.
  ///
  /// So the budget follows the selector you passed:
  ///
  /// - xpath only, no match: **~10 s** — tiers 1-2 are skipped outright.
  /// - a11y-id + xpath, neither matching: ~20 s.
  /// - a11y-id + label + xpath, none matching: **~30 s**, the worst case, before
  ///   tier 4 synthesizes a rect-center.
  ///
  /// Two tiers are cheaper than they look: tier 2 only issues a find when
  /// [cached] already contains a label match, and tier 4 is pure arithmetic
  /// with no device round-trip at all.
  ///
  /// An outer loop therefore multiplies: 20 attempts around a fully-missing
  /// selector is ~10 minutes, which presents as a hang rather than a failure.
  /// If you are polling for a condition (an overlay clearing, a page settling),
  /// prefer detecting it directly over discovering it through a resolve
  /// failure, and keep the outer count small.
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
  ///
  /// WHEN A PLATFORM OVERLAY HIDES THE FIELD this throws
  /// [NativeException] with [NativeException.fieldObscuredCode] and does NOT
  /// recover — it holds a resolved [target] and cannot re-resolve the handle
  /// that dismissal invalidates. Recovery is automatic only through the
  /// `enter_text` TOOL; a backend-direct caller must implement it. The full
  /// recipe is on [NativeException.fieldObscuredCode].
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  );

  /// A logical platform action. Shared: `enter`|`return`|`done`. iOS-only:
  /// `consent_accept`|`alert_dismiss`; `consent_accept` issues
  /// `POST /session/{id}/alert/accept` and `alert_dismiss` issues
  /// `POST /session/{id}/alert/dismiss`. Android-only: `back` and the internal
  /// positively-gated `dismiss_overlay` recovery action. An unrecognized key
  /// throws [NativeException]; an alert-endpoint key issued when no alert is
  /// open surfaces the W3C "no alert open" error as a [NativeException].
  Future<void> press(String key);

  /// Swipe gesture (W3C actions / `mobile: swipe`).
  Future<void> swipe(NativeSwipe gesture);

  /// Tear down the device session and any HTTP client. Does NOT stop Appium or
  /// shut down the sim.
  Future<void> close();
}
