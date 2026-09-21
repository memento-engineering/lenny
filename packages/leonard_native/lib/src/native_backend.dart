/// The `NativeBackend` seam — the I/O boundary that keeps `buildPerception()`
/// synchronous (the pull-free build invariant). ALL device latency (WebDriver
/// round-trips, a11y-tree polling) lives behind it; the extension never
/// touches the device directly.
///
/// `XcuiTestBackend` (iOS), `UiAutomator2Backend` (Android), and `Mac2Backend`
/// (macOS) are the concrete impls; `FakeNativeBackend` is the test impl.
library;

import 'package:meta/meta.dart';

import 'native_snapshot.dart';

/// Resolved target of a native action — what the selector chain produced.
///
/// [elementId] is the backend's W3C element handle when one resolved
/// (resource-id / a11y-id / label / xpath tier); when only rect-center
/// resolved, [elementId] is null and the backend taps [point].
@immutable
class NativeTarget {
  /// Records the resolved [elementId] and/or [point], and which tier [via] won.
  const NativeTarget({this.elementId, this.point, required this.via});

  /// W3C `element-6066-...` handle, or null (rect-center).
  final String? elementId;

  /// Rect-center fallback coordinate, or null.
  final ({int x, int y})? point;

  /// `resource-id` | `a11y-id` | `label` | `xpath` | `rect-center`.
  final String via;
}

/// A selector spec carrying the raw tool args for the resolution chain.
@immutable
class NativeSelector {
  /// Records the per-tier selector args.
  const NativeSelector({
    this.resourceId,
    this.a11yId,
    this.label,
    this.xpath,
    this.rect,
  });

  /// Selects the clickable Android node for Flutter's
  /// `Semantics(identifier:)` projection.
  ///
  /// Flutter projects the identifier onto a `resource-id` node. WHETHER that
  /// node is itself clickable VARIES BY DEVICE AND OS VERSION: a Pixel 7a on
  /// Android 16 puts it on a non-clickable node whose actionable parent is an
  /// anonymous ancestor, while a Samsung SM-M225FV on Android 13 makes the
  /// identifier node clickable itself (measured live on RF8RB21P6LN). The
  /// `ancestor-or-self` axis below is what makes this helper correct on both —
  /// it climbs when it must and stops at self when it need not, so no caller
  /// needs a per-device branch.
  ///
  /// Android-specific; it does not reinterpret a missed [a11yId].
  factory NativeSelector.flutterIdentifier(String identifier) => NativeSelector(
    xpath:
        '//*[@resource-id=${xpathLiteral(identifier)}]'
        '/ancestor-or-self::*[@clickable="true"][1]',
  );

  /// Android tier 1: exact `resource-id`. Skipped on iOS and macOS.
  ///
  /// The a11y tree carries TWO kinds of `resource-id`, and they resolve
  /// differently (measured on a Pixel 7a / Android 16 / Chrome 150, Appium
  /// uiautomator2 8.2.2 — GitHub #51):
  ///
  /// * a NATIVE view's resource name (`pkg:id/name`, e.g.
  ///   `android:id/content`) — the live `using=id` locator matches it;
  /// * a WEB-CONTENT id synthesized from the HTML `id` attribute of an
  ///   element inside Chrome (bare, e.g. `email`) — present in the serialized
  ///   tree and matchable by XPath over it, but INVISIBLE to `using=id`,
  ///   which only consults real view resource names.
  ///
  /// The backend resolves both: `using=id` first, and on a miss a bare value
  /// (no `:id/`) falls through to `//*[@resource-id='…']` over the serialized
  /// tree (`via: 'resource-id-xpath'`). A `pkg:id/name` value that misses is
  /// a genuine miss and does NOT fall through.
  final String? resourceId;

  /// Android tier 2 / iOS and macOS tier 1: a11y identifier.
  final String? a11yId;

  /// Android tier 3 / iOS and macOS tier 2: visible label (matched against
  /// `node.label`).
  final String? label;

  /// Android tier 4 / iOS and macOS tier 3: XPath (load-bearing for anonymous
  /// fields).
  final String? xpath;

  /// Android tier 5 / iOS and macOS tier 4: `[l,t,r,b]`; tap at its center.
  final List<int>? rect;
}

/// Quotes [value] as an XPath 1.0 string literal, taking the `concat()` path
/// when it carries both quote kinds. Package-internal (not exported by the
/// barrel): shared by [NativeSelector.flutterIdentifier] and
/// `UiAutomator2Backend`'s bare-resource-id fallback — one quoting
/// implementation, not two.
String xpathLiteral(String value) {
  if (!value.contains("'")) return "'$value'";
  if (!value.contains('"')) return '"$value"';
  final List<String> parts = value.split("'");
  return 'concat(${parts.map((String part) => "'$part'").join(', "\'", ')})';
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

/// The seam the watcher drives and the tools act through. Appium backends
/// implement iOS, Android, and macOS; `FakeNativeBackend` is the test impl.
/// Per-platform behavior (iOS ASWebAuthenticationSession consent, mobile
/// keyboard dismissal, macOS key injection, readback attributes) lives INSIDE
/// the impl, never in the extension/tools.
///
/// Recognized [press] keys are platform-specific and documented on the impl,
/// NOT enforced by an allowlist on the tool. All three platforms recognize
/// `enter`/`return`/`done`; the iOS-only set is
/// `consent_accept`/`alert_dismiss`; the Android-only set is `back`, the
/// internal `dismiss_overlay` recovery action, and
/// `permission_allow`/`permission_deny`. An unrecognized key surfaces as a
/// [NativeException] from the impl.
abstract class NativeBackend {
  /// Open the session against an ALREADY-RUNNING Appium server and target. The
  /// backend does NOT spawn Appium, boot a simulator, or launch helper
  /// processes. Idempotent.
  ///
  /// [extraCapabilities] are merged over orthogonal Appium defaults when a new
  /// session is created. Attach-critical capabilities are rejected with
  /// [ArgumentError].
  Future<void> connect({
    Map<String, Object?> extraCapabilities = const <String, Object?>{},
  });

  /// Out-of-band poll loop: emits a fresh [NativeSnapshot] each tick (reading
  /// `/source` for Appium and parsing the platform XML). This is the watcher's
  /// source — the snapshot IS the event payload.
  Stream<NativeSnapshot> watch();

  /// One-shot capture for seeding the cache in `initialize()` and for the
  /// post-action refresh tools call (the poll loop may not have ticked since
  /// the tap/text). Same payload shape as a [watch] event.
  Future<NativeSnapshot> snapshot();

  /// Resolve [selector] against the device into a [NativeTarget], walking the
  /// Android walks resource-id -> a11y-id -> label -> xpath -> rect-center.
  /// iOS and macOS have no resource-id lookup and skip that field, walking
  /// a11y-id -> label -> xpath -> rect-center. Returns null when nothing
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
  /// - xpath only, no match: **~10 s** — earlier null tiers are skipped outright.
  /// - a11y-id + xpath, neither matching: ~20 s.
  /// - a11y-id + label + xpath, none matching: **~30 s** before rect-center.
  /// - Android resource-id + a11y-id + label + xpath, none matching: **~40 s**
  ///   before rect-center, the maximum when every find tier is populated.
  ///
  /// Two tiers are cheaper than they look: label only issues a find when
  /// [cached] already contains a label match, and rect-center is pure arithmetic
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

  /// Clear + type [text] into [target], dismissing a mobile keyboard where the
  /// platform supports it. Returns `(readback, masked)`: `readback` is the
  /// platform value attribute; `masked` is derived from the ELEMENT TYPE (true
  /// iff the element is a SecureTextField), NOT from `readback != text`.
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

  /// A logical platform action. Shared by iOS, Android, and macOS:
  /// `enter`|`return`|`done`. iOS-only:
  /// `consent_accept`|`alert_dismiss`; `consent_accept` issues
  /// `POST /session/{id}/alert/accept` and `alert_dismiss` issues
  /// `POST /session/{id}/alert/dismiss`. Android-only: `back`, the internal
  /// positively-gated `dismiss_overlay` recovery action, and
  /// `permission_allow`/`permission_deny`.
  ///
  /// `dismiss_overlay` refuses an Android permission dialog because Android
  /// Back denies permission. Denial persistently changes application behavior;
  /// granting is still less reversible and was not requested. Consumers must
  /// express either intent through its explicit permission key. An unrecognized
  /// key throws [NativeException]; an alert-endpoint key issued when no alert
  /// is open surfaces the W3C "no alert open" error as a [NativeException].
  Future<void> press(String key);

  /// Swipe gesture using the platform's W3C pointer actions.
  Future<void> swipe(NativeSwipe gesture);

  /// Tear down the session and any HTTP client. Does NOT stop Appium, shut down
  /// a simulator, or terminate a macOS app attached with `skipAppKill`.
  Future<void> close();
}
