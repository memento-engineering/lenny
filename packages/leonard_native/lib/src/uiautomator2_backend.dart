/// `UiAutomator2Backend` — the concrete [NativeBackend] over W3C WebDriver HTTP
/// against a local Appium server running the **UiAutomator2** driver (Android).
///
/// The Android sibling of `XcuiTestBackend` (seam contract,
/// `native_backend.dart`). The generic W3C transport (session, `/element` find,
/// the 4-tier resolve chain, pointer-action tap/swipe) is identical to the iOS
/// impl; only the Android divergences live here, per the seam's "all platform
/// quirks inside the impl" rule:
///
///   * `/source` is a UiAutomator2 tree (`<hierarchy>` of `android.widget.*` /
///     `android.view.*` elements) — a different parser from XCUITest;
///   * the tier-1 accessibility id on UiAutomator2 is the element's
///     `content-desc` (NOT `resource-id`), so [NativeNode.a11yId] carries
///     `content-desc` and the resolver's `_find('accessibility id', …)` matches;
///   * [enterText] masks from `GET .../attribute/password == 'true'` (Android
///     has no `SecureTextField` type), and reads back via `GET .../attribute/
///     text` (FN4), then dismisses the keyboard with `POST /back` — but ONLY
///     when `is_keyboard_shown` says one is up, because a bare back is
///     navigation, not a dismiss (non-fatal, B6). It writes via
///     `POST .../value` and, when that answers
///     `invalid element state`, FALLS BACK to `click` + `mobile: type` —
///     Chrome's web `<input>` nodes (any Custom Tab / WebView, so every OAuth
///     handoff) reject `ACTION_SET_TEXT` while accepting injected key events.
///     `/keys` is NOT the fallback: it shares the ACTION_SET_TEXT handler for
///     arbitrary text and fails identically (see the note at the call site);
///   * [press] recognizes `back` (`POST /back`) and `enter`/`return`/`done`
///     (a newline via `/keys`); the iOS-only alert keys `consent_accept` /
///     `alert_dismiss` throw [NativeException] (Android's Auth0 handoff is a
///     Chrome Custom Tab with no SpringBoard consent/save-password alert).
///
/// All device latency lives here so `buildPerception()` stays synchronous —
/// the pull-free build invariant. The backend does NOT boot the emulator or
/// spawn Appium.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import 'native_backend.dart';
import 'native_snapshot.dart';

/// The W3C element key returned by every successful `find`.
const String _w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// `bounds="[l,t][r,b]"` — the UiAutomator2 rect encoding.
final RegExp _boundsRe = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');

/// Drives a native Android app over a local Appium server (W3C WebDriver +
/// UiAutomator2).
class UiAutomator2Backend implements NativeBackend {
  /// Constructs a backend targeting [udid] + [app] on [server] (default
  /// `http://127.0.0.1:4723`). The backend does NOT spawn Appium or boot the
  /// emulator — both must already be running. [platform] is fixed `android`.
  UiAutomator2Backend({
    Uri? server,
    required this.udid,
    required this.app,
    this.pollInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : server = server ?? Uri.parse('http://127.0.0.1:4723'),
       _client = client ?? http.Client();

  /// The local Appium server URL.
  final Uri server;

  /// The booted emulator/device udid (e.g. `emulator-5554`).
  final String udid;

  /// The Android application under test — an `.apk` path or an application
  /// package id. Retained for parity with the iOS impl; the dual-attach session
  /// uses `autoLaunch:false` and attaches to the foreground app, so a running
  /// `flutter run` process is NOT relaunched.
  final String app;

  /// The watcher poll cadence.
  final Duration pollInterval;

  /// Fixed platform tag emitted on every [NativeSnapshot].
  final String platform = 'android';

  final http.Client _client;

  /// The active W3C session id, or null before [connect] / after [close].
  String? _sessionId;

  // ---------------------------------------------------------------------------
  // Transport (the platform-neutral W3C machinery, with the B5 hardening).
  // ---------------------------------------------------------------------------

  Uri _u(String path) => server.resolve(path);

  /// Throws [NativeException] (never `StateError`) when no session is open.
  String get _sid =>
      _sessionId ?? (throw NativeException('no session: call connect() first'));

  Future<Map<String, Object?>> _post(String path, Object body) async {
    final http.Response r = await _client.post(
      _u(path),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    return _unwrap(r);
  }

  Future<Map<String, Object?>> _get(String path) async {
    final http.Response r = await _client.get(_u(path));
    return _unwrap(r);
  }

  /// B5: honor the HTTP status first; on non-2xx OR a `value.error` envelope
  /// throw [NativeException]. A non-JSON / HTML / empty body throws
  /// `NativeException('non-JSON response: …')`, NEVER a bare `FormatException`
  /// — so `_find`'s retry guard stays load-bearing.
  Map<String, Object?> _unwrap(http.Response r) {
    Object? decoded;
    try {
      decoded = r.body.isEmpty ? null : jsonDecode(r.body);
    } on FormatException {
      throw NativeException(
        'non-JSON response: HTTP ${r.statusCode}: ${_truncate(r.body)}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw NativeException(
        'non-JSON response: HTTP ${r.statusCode}: ${_truncate(r.body)}',
      );
    }
    final Object? value = decoded['value'];
    if (value is Map && value['error'] != null) {
      // The message keeps the code as a prefix — it is model-facing, so its
      // text is unchanged by carrying `code` structurally alongside it.
      throw NativeException(
        '${value['error']}: ${value['message'] ?? ''}'.trim(),
        code: value['error'].toString(),
      );
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw NativeException('HTTP ${r.statusCode}: ${_truncate(r.body)}');
    }
    return decoded;
  }

  static String _truncate(String s) =>
      s.length <= 400 ? s : '${s.substring(0, 400)}…';

  // ---------------------------------------------------------------------------
  // Session lifecycle.
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect() async {
    if (_sessionId != null) return; // idempotent
    // Attach to the foreground app (the running `flutter run` process) WITHOUT
    // relaunching it: UiAutomator2 with `autoLaunch:false` and no app/appPackage
    // cap starts a session against whatever is on screen. This is the Android
    // analogue of iOS's "never terminate the Flutter process" invariant — a
    // relaunch would drop the flutter_ws channel the dual round-trip needs.
    final Map<String, Object?> caps = <String, Object?>{
      'platformName': 'Android',
      'appium:automationName': 'UiAutomator2',
      'appium:udid': udid,
      'appium:noReset': true,
      'appium:autoLaunch': false,
      'appium:newCommandTimeout': 0,
    };
    final Map<String, Object?> j = await _post('/session', <String, Object?>{
      'capabilities': <String, Object?>{
        'alwaysMatch': caps,
        'firstMatch': <Object?>[<String, Object?>{}],
      },
    });
    final Object? value = j['value'];
    final String? sid = value is Map
        ? (value['sessionId'] ?? j['sessionId']) as String?
        : j['sessionId'] as String?;
    if (sid == null) {
      throw NativeException('session open returned no sessionId');
    }
    _sessionId = sid;
  }

  @override
  Future<void> close() async {
    final String? sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try {
        await _client.delete(_u('/session/$sid'));
      } on Object {
        // best-effort: releasing the UiAutomator2 session must never throw.
      }
    }
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Observation: poll /source -> parse the UiAutomator2 XML -> NativeSnapshot.
  // ---------------------------------------------------------------------------

  @override
  Stream<NativeSnapshot> watch() async* {
    while (_sessionId != null) {
      await Future<void>.delayed(pollInterval);
      if (_sessionId == null) break;
      yield await snapshot();
    }
  }

  @override
  Future<NativeSnapshot> snapshot() async {
    final Map<String, Object?> j = await _get('/session/$_sid/source');
    final String xml = (j['value'] ?? '').toString();
    return NativeSnapshot(platform: platform, nodes: _parseSource(xml));
  }

  // ---------------------------------------------------------------------------
  // The UiAutomator2 /source XML parser.
  // ---------------------------------------------------------------------------

  /// Map an Android widget `class` to the Flutter role vocabulary.
  static String _role(String cls) {
    switch (cls) {
      case 'android.widget.Button':
      case 'android.widget.ImageButton':
        return 'button';
      case 'android.widget.EditText':
      case 'android.widget.AutoCompleteTextView':
        return 'textfield';
      case 'android.widget.ImageView':
        return 'image';
      case 'android.widget.Switch':
      case 'android.widget.CheckBox':
      case 'android.widget.ToggleButton':
      case 'android.widget.CompoundButton':
        return 'switch';
      default:
        return 'text';
    }
  }

  /// Parse `bounds="[l,t][r,b]"` into `[l,t,r,b]`; `[0,0,0,0]` when absent.
  static List<int> _rect(String? bounds) {
    if (bounds == null) return const <int>[0, 0, 0, 0];
    final RegExpMatch? m = _boundsRe.firstMatch(bounds);
    if (m == null) return const <int>[0, 0, 0, 0];
    return <int>[
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    ];
  }

  /// Parse a raw UiAutomator2 `/source` XML document into the flattened,
  /// filtered list of [NativeNode]s in document order. Exposed for the parser
  /// unit test — the Android analogue of `XcuiTestBackend.parseSource`.
  @visibleForTesting
  List<NativeNode> parseSource(String xml) => _parseSource(xml);

  List<NativeNode> _parseSource(String xml) {
    final XmlDocument doc = XmlDocument.parse(xml);

    // Pass 1: keep the signal-bearing elements, count per-class for positional
    // xpath, and record resource-id uniqueness per class.
    final List<XmlElement> kept = <XmlElement>[];
    final Map<String, int> classCount = <String, int>{};
    final Map<XmlElement, int> classIndex = <XmlElement, int>{};
    final Map<String, int> ridCountByClass = <String, int>{};

    for (final XmlElement el in doc.descendantElements) {
      final String cls = _className(el);
      final String? text = _attr(el, 'text');
      final String? desc = _attr(el, 'content-desc');
      final String? rid = _attr(el, 'resource-id');
      final String role = _role(cls);

      // Filter: drop pure structural containers — no text/content-desc/
      // resource-id AND the class maps to the default `text` role.
      final bool hasSignal = text != null || desc != null || rid != null;
      if (!hasSignal && role == 'text') continue;

      kept.add(el);
      final int idx = (classCount[cls] ?? 0) + 1;
      classCount[cls] = idx;
      classIndex[el] = idx;
      if (rid != null) {
        ridCountByClass['$cls $rid'] = (ridCountByClass['$cls $rid'] ?? 0) + 1;
      }
    }

    // Pass 2: materialize NativeNodes with dense document-order ids.
    final List<NativeNode> out = <NativeNode>[];
    int id = 0;
    for (final XmlElement el in kept) {
      final String cls = _className(el);
      final String? text = _attr(el, 'text');
      final String? desc = _attr(el, 'content-desc');
      final String? rid = _attr(el, 'resource-id');
      final String role = _role(cls);

      out.add(
        NativeNode(
          id: ++id,
          role: role,
          // Human label: prefer the visible `text`, fall back to `content-desc`.
          label: text ?? desc,
          // Editable content only (an EditText's current text); non-fields omit.
          value: role == 'textfield' ? text : null,
          rect: _rect(el.getAttribute('bounds')),
          // Tier-1 accessibility id on UiAutomator2 IS `content-desc`.
          a11yId: desc,
          xpath: _xpathFor(el, cls, rid, classIndex, ridCountByClass),
          // For Dart consumers needing a stable, non-localising key (overlay
          // detection). Deliberately NOT wired — see NativeNode.resourceId.
          resourceId: rid,
        ),
      );
    }
    return out;
  }

  /// An element's Android `class` — the `class` attribute, else the tag name.
  static String _className(XmlElement el) =>
      el.getAttribute('class') ?? el.name.local;

  /// Read an attribute, normalizing empty strings to null.
  static String? _attr(XmlElement el, String key) {
    final String? v = el.getAttribute(key);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Deterministic xpath synthesis: prefer a unique `[@resource-id=…]` xpath;
  /// otherwise a positional `(//<class>)[n]` by 1-based document-order index
  /// among kept nodes of that class (the Android analogue of iOS's
  /// name-or-positional rule, keyed on `resource-id` rather than `name`).
  static String _xpathFor(
    XmlElement el,
    String cls,
    String? rid,
    Map<XmlElement, int> classIndex,
    Map<String, int> ridCountByClass,
  ) {
    if (rid != null && (ridCountByClass['$cls $rid'] ?? 0) == 1) {
      return "//$cls[@resource-id='$rid']";
    }
    return '(//$cls)[${classIndex[el]}]';
  }

  // ---------------------------------------------------------------------------
  // Resolution: the 4-tier selector chain (identical to iOS).
  // ---------------------------------------------------------------------------

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) async {
    // Tier 1: a11y-id (on UiAutomator2, the element's content-desc).
    if (selector.a11yId != null) {
      final String? eid = await _find('accessibility id', selector.a11yId!);
      if (eid != null) return NativeTarget(elementId: eid, via: 'a11y-id');
    }

    // Tier 2: label -> the matched cached node's a11yId / synthesized xpath.
    if (selector.label != null) {
      final NativeNode? node = _matchLabel(cached, selector.label!);
      if (node != null) {
        String? eid;
        if (node.a11yId != null && node.a11yId!.isNotEmpty) {
          eid = await _find('accessibility id', node.a11yId!);
        } else if (node.xpath != null && node.xpath!.isNotEmpty) {
          eid = await _find('xpath', node.xpath!);
        }
        if (eid != null) return NativeTarget(elementId: eid, via: 'label');
      }
    }

    // Tier 3: explicit xpath (load-bearing for anonymous web-form fields).
    if (selector.xpath != null) {
      final String? eid = await _find('xpath', selector.xpath!);
      if (eid != null) return NativeTarget(elementId: eid, via: 'xpath');
    }

    // Tier 4: rect-center — from the selector rect, or a cached node rect.
    final List<int>? rect = selector.rect ?? _cachedRect(cached, selector);
    if (rect != null && rect.length == 4) {
      return NativeTarget(
        point: (
          x: ((rect[0] + rect[2]) / 2).round(),
          y: ((rect[1] + rect[3]) / 2).round(),
        ),
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

  List<int>? _cachedRect(NativeSnapshot? cached, NativeSelector selector) {
    if (cached == null || selector.label == null) return null;
    return _matchLabel(cached, selector.label!)?.rect;
  }

  /// Find one element via a W3C strategy, retrying with a short timeout so a
  /// transient miss does not fail the whole resolution. Returns null when the
  /// element never appears within the window.
  Future<String?> _find(
    String strategy,
    String value, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final DateTime end = DateTime.now().add(timeout);
    while (true) {
      try {
        final Map<String, Object?> j = await _post(
          '/session/$_sid/element',
          <String, Object?>{'using': strategy, 'value': value},
        );
        final Object? v = j['value'];
        if (v is Map) {
          final Object? eid = v[_w3cElementKey] ?? v.values.first;
          if (eid is String) return eid;
        }
        return null;
      } on NativeException {
        if (!DateTime.now().isBefore(end)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Actions.
  // ---------------------------------------------------------------------------

  @override
  Future<void> tap(NativeTarget target) async {
    if (target.elementId != null) {
      await _post(
        '/session/$_sid/element/${target.elementId}/click',
        const <String, Object?>{},
      );
      return;
    }
    final ({int x, int y})? p = target.point;
    if (p == null) {
      throw NativeException('tap: target has neither elementId nor point');
    }
    // W3C pointer action: a tap at the rect-center point.
    await _post('/session/$_sid/actions', <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'pointer',
          'id': 'finger1',
          'parameters': <String, Object?>{'pointerType': 'touch'},
          'actions': <Object?>[
            <String, Object?>{
              'type': 'pointerMove',
              'duration': 0,
              'x': p.x,
              'y': p.y,
            },
            <String, Object?>{'type': 'pointerDown', 'button': 0},
            <String, Object?>{'type': 'pause', 'duration': 50},
            <String, Object?>{'type': 'pointerUp', 'button': 0},
          ],
        },
      ],
    });
  }

  @override
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  ) async {
    final String? eid = target.elementId;
    if (eid == null) {
      throw NativeException('enter_text requires a resolved element');
    }
    await _post('/session/$_sid/element/$eid/clear', const <String, Object?>{});
    try {
      await _post('/session/$_sid/element/$eid/value', <String, Object?>{
        'text': text,
      });
    } on NativeException catch (e) {
      // UiAutomator2 implements `/value` as
      // AccessibilityNodeInfo.performAction(ACTION_SET_TEXT). Chrome's web
      // `<input>` nodes (a Custom Tab / WebView — every OAuth handoff) do not
      // honour that action and answer `invalid element state`, even though the
      // field is writable by injected key events (`adb shell input text`
      // lands). So fall back to key-event injection.
      //
      // Branching on `code` rather than the message text is deliberate: a
      // reworded remote message must not be able to silently disable this.
      if (e.code != 'invalid element state') rethrow;

      final String? obstruction = await _detectObstruction();
      if (obstruction != null) {
        throw NativeException(
          'enter_text field is obscured by $obstruction; automatic recovery may '
          'dismiss it and retry once.',
          code: NativeException.fieldObscuredCode,
        );
      }

      // NOT `/keys`. Measured on a real device (SM-M225FV, Android 13,
      // Chrome 150, Appium 3.5.2 / uiautomator2 8.2.2): `POST /keys` with
      // arbitrary text routes to the SAME SendKeysToElement ->
      // ACTION_SET_TEXT handler and fails with the SAME
      // `invalid element state`. [press] gets away with `/keys` only because
      // a NEWLINE is handled as a key event, not as a set-text — so `press`
      // working proves nothing about typing text.
      //
      // The click is LOAD-BEARING: `clear` does not leave the element
      // focused (`attribute/focused` reads false right after it), and
      // `mobile: type` against an unfocused element returns HTTP 200 while
      // typing NOTHING. A silent no-op that reports success is the worst
      // failure shape available, so the click must not be dropped — and the
      // readback below is what would catch it.
      //
      // Note for consumers: clicking a Chrome field can raise the
      // Touch-To-Fill "Use saved password?" sheet, and this fallback turns a
      // previously-FAILING enterText into a succeeding one, so a recovery
      // path keyed on that failure will stop firing.
      await _post(
        '/session/$_sid/element/$eid/click',
        const <String, Object?>{},
      );

      // Refuse to type into the void. `mobile: type` reports success
      // regardless, so without this check an obstructed field yields HTTP 200
      // and an empty readback — which for a MASKED field is indistinguishable
      // from a correct write, since Android never reads a secret back.
      //
      // `attribute/focused` is a reliable discriminator here (measured: false
      // after `clear`, true after `click` on a writable field). The known
      // obstruction is Chrome's Touch-To-Fill "Use saved password?" sheet,
      // which both makes Chrome refuse ACTION_SET_TEXT and swallows injected
      // keystrokes — so failing loudly with the cause named beats a silent
      // no-op the caller has to infer.
      if (!await _isFocused(eid)) {
        throw NativeException(
          'enter_text could not focus the element after click, so the '
          'keystroke fallback would have typed nothing. The field is likely '
          'obscured — on Chrome this is usually the Touch-To-Fill "Use saved '
          'password?" sheet, which also blocks ACTION_SET_TEXT. Dismiss the '
          'obstruction, then retry.',
        );
      }

      await _post('/session/$_sid/execute/sync', <String, Object?>{
        'script': 'mobile: type',
        'args': <Object?>[
          <String, Object?>{'text': text},
        ],
      });
    }
    // Android masks from the element's `password` attribute (there is no
    // SecureTextField type). A password EditText reads back EMPTY via
    // attribute/text (Android never exposes the entered secret) — the seam's
    // `masked` contract holds regardless: masked is attribute-derived, not
    // `readback != text`.
    final bool masked = await _isSecureField(eid);
    final String readback = await _readValue(eid);
    // Per-platform keyboard dismiss, INSIDE the backend (kept off the seam).
    await _dismissKeyboard();
    return (readback: readback, masked: masked);
  }

  static const String _chromeBottomSheetId =
      'com.android.chrome:id/bottom_sheet';
  static const String _touchToFillTitleId =
      'com.android.chrome:id/touch_to_fill_sheet_title';

  String? _obstructionName(NativeSnapshot source) {
    final bool hasBottomSheet = source.nodes.any(
      (NativeNode node) => node.resourceId == _chromeBottomSheetId,
    );
    if (!hasBottomSheet) return null;
    final bool isTouchToFill = source.nodes.any(
      (NativeNode node) => node.resourceId == _touchToFillTitleId,
    );
    return isTouchToFill ? 'Chrome Touch-To-Fill sheet' : 'Chrome bottom sheet';
  }

  /// The obstruction probe, which reads a fresh `/source`.
  ///
  /// Fails SAFE toward NOT reporting an obstruction — the same direction the
  /// keyboard gate takes. This runs inside the `invalid element state` handler,
  /// which before this probe existed ALWAYS reached the click + `mobile: type`
  /// fallback. Reading `/source` adds two new ways for that handler to abort: a
  /// transport failure ([NativeException]) and a malformed body, where
  /// `XmlDocument.parse` throws an `XmlParserException` that is not a
  /// [NativeException] at all and would escape the tool layer's
  /// `on NativeException catch`. Swallowing both restores the prior guarantee
  /// exactly: an unreadable `/source` reads as "nothing obstructing", the write
  /// still attempts its fallback, and the readback check remains the thing that
  /// catches a silently-empty write.
  Future<String?> _detectObstruction() async {
    try {
      return _obstructionName(await snapshot());
    } on Object {
      return null;
    }
  }

  /// FN4 (Android): the field value is `attribute/text`.
  Future<String> _readValue(String eid) async {
    final Map<String, Object?> j = await _get(
      '/session/$_sid/element/$eid/attribute/text',
    );
    return (j['value'] ?? '').toString();
  }

  /// True iff the element currently holds input focus.
  ///
  /// Read by the [enterText] keystroke fallback, which cannot land anything
  /// on an unfocused element. Unlike [_isSecureField] this does NOT swallow a
  /// transport failure: the fallback needs to distinguish "not focused" from
  /// "could not tell", and treating an unreadable attribute as unfocused would
  /// turn a transient error into a spurious obstruction report.
  Future<bool> _isFocused(String eid) async {
    final Map<String, Object?> j = await _get(
      '/session/$_sid/element/$eid/attribute/focused',
    );
    return (j['value'] ?? '').toString() == 'true';
  }

  /// True iff the element's `password` attribute is `true` (UiAutomator2's
  /// masked-field signal; the Android analogue of the iOS SecureTextField type).
  Future<bool> _isSecureField(String eid) async {
    try {
      final Map<String, Object?> j = await _get(
        '/session/$_sid/element/$eid/attribute/password',
      );
      return (j['value'] ?? '').toString() == 'true';
    } on NativeException {
      return false;
    }
  }

  /// Android keyboard dismiss: `POST /back`, but ONLY when a soft keyboard is
  /// actually shown. Non-fatal (B6) — a dismiss failure must never fail the
  /// type.
  ///
  /// The gate is load-bearing, not defensive tidiness. `back` is Android's
  /// dismiss gesture only WHILE a keyboard holds focus; with none up it is
  /// plain navigation. `setValue` / `mobile: type` do not raise the soft
  /// keyboard, so on a Chrome page there is nothing to dismiss and an
  /// unconditional back navigates the CUSTOM TAB AWAY — measured, and it
  /// stranded a real Auth0 login: the write succeeded, the back left the page,
  /// and every subsequent field lookup 404'd against an app no longer showing
  /// the form.
  ///
  /// The `on Object` catch below does NOT protect against that. The stray back
  /// returns 200 — it SUCCEEDS at doing the wrong thing, and "non-fatal" only
  /// ever guarded against errors. Only the gate helps.
  ///
  /// This also brings Android in line with the iOS impl, which already probes
  /// for a `Done` key and clicks only when one is present.
  Future<void> _dismissKeyboard() async {
    try {
      // Fail SAFE toward NOT acting: if the keyboard state cannot be read,
      // press nothing. A keyboard left up is trivially recoverable; a spurious
      // back is not. A throw from _isKeyboardShown lands in the catch below,
      // which returns without pressing — deliberately.
      if (!await _isKeyboardShown()) return;
      await _post('/session/$_sid/back', const <String, Object?>{});
    } on Object {
      // Non-fatal: dismiss is best-effort.
    }
  }

  /// True iff a soft keyboard is currently shown.
  Future<bool> _isKeyboardShown() async {
    final Map<String, Object?> j = await _get(
      '/session/$_sid/appium/device/is_keyboard_shown',
    );
    return j['value'].toString() == 'true';
  }

  @override
  Future<void> press(String key) async {
    switch (key) {
      case 'dismiss_overlay':
        if (await _detectObstruction() == null) {
          throw NativeException('no dismissible platform overlay is present');
        }
        await press('back');
        return;
      case 'back':
        await _post('/session/$_sid/back', const <String, Object?>{});
        return;
      case 'enter':
      case 'return':
      case 'done':
        // Inject a newline keystroke into the active element.
        await _post('/session/$_sid/keys', <String, Object?>{
          'value': <String>['\n'],
        });
        return;
      case 'consent_accept':
      case 'alert_dismiss':
        // iOS-only (ASWebAuthenticationSession consent / SpringBoard alert).
        // Android's Auth0 handoff is a Chrome Custom Tab — no system alert — so
        // these surface as a NativeException (ok:false), which an adaptive
        // caller tolerates as a no-op.
        throw NativeException('unknown press key: $key (iOS-only)');
      default:
        throw NativeException('unknown press key: $key');
    }
  }

  @override
  Future<void> swipe(NativeSwipe gesture) async {
    await _post('/session/$_sid/actions', <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'pointer',
          'id': 'finger1',
          'parameters': <String, Object?>{'pointerType': 'touch'},
          'actions': <Object?>[
            <String, Object?>{
              'type': 'pointerMove',
              'duration': 0,
              'x': gesture.fromX,
              'y': gesture.fromY,
            },
            <String, Object?>{'type': 'pointerDown', 'button': 0},
            <String, Object?>{
              'type': 'pointerMove',
              'duration': gesture.durationMs,
              'x': gesture.toX,
              'y': gesture.toY,
            },
            <String, Object?>{'type': 'pointerUp', 'button': 0},
          ],
        },
      ],
    });
  }
}
