/// `AppiumBackend` — the concrete [NativeBackend] over W3C WebDriver HTTP
/// against a local Appium server running XCUITest (iOS).
///
/// A hardened production lift of `docs/design/leonard-native-appium/
/// backend_skeleton.dart`, reproducing the proven spike recipe
/// (`~/lenny-spike/RESULTS.md`, GREEN 2026-06-20: Appium 3.5.2 +
/// appium-xcuitest-driver 11.12.2, Xcode 26.5, iOS 26 sim). All device latency
/// (WebDriver round-trips, `/source` polling) lives here so the extension's
/// `buildPerception()` stays synchronous (ADR-0006).
///
/// Hardening applied (m2-spec §5.5): B5 (`_unwrap` honors HTTP status +
/// non-JSON bodies → [NativeException], never `FormatException`), FN3
/// (`enterText` masked flag is element-type-derived, NOT `readback != text`),
/// FN4 (`readValue` branches iOS `attribute/value` vs Android `attribute/text`),
/// B6 (Android keyboard dismiss is non-fatal), B8 (`udid`/`app` required, no
/// `bundleId`/`deviceName` caps), plus the skeleton-lift deletions: the
/// xpath-based "Continue" consent find is GONE — consent is
/// `POST /session/{id}/alert/accept` (`press('consent_accept')`), because the
/// SpringBoard consent is not in `/source`.
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

/// Drives a native iOS app over a local Appium server (W3C WebDriver +
/// XCUITest).
class AppiumBackend implements NativeBackend {
  /// Constructs a backend targeting [udid] + [app] on [server] (default
  /// `http://127.0.0.1:4723`). The backend does NOT spawn Appium or boot the
  /// simulator — both must already be running.
  AppiumBackend({
    Uri? server,
    required this.platform,
    required this.udid,
    required this.app,
    this.osVersion = '26',
    this.pollInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : server = server ?? Uri.parse('http://127.0.0.1:4723'),
       _client = client ?? http.Client();

  /// The local Appium server URL.
  final Uri server;

  /// Target platform — `ios` for m2 (`android` deferred).
  final String platform;

  /// The booted simulator udid.
  final String udid;

  /// Path to the `.app` bundle to install/launch.
  final String app;

  /// The simulator OS version.
  final String osVersion;

  /// The watcher poll cadence.
  final Duration pollInterval;

  final http.Client _client;

  /// The active W3C session id, or null before [connect] / after [close].
  String? _sessionId;

  bool get _ios => platform == 'ios';

  // ---------------------------------------------------------------------------
  // Transport (lifted from the skeleton WITH the B5 hardening).
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
  /// throw [NativeException] (with status + raw body). A non-JSON / HTML /
  /// empty body throws `NativeException('non-JSON response: …')`, NEVER a bare
  /// `FormatException` — so `find`'s retry guard stays load-bearing.
  Map<String, Object?> _unwrap(http.Response r) {
    Object? decoded;
    try {
      decoded = r.body.isEmpty ? null : jsonDecode(r.body);
    } on FormatException {
      throw NativeException(
        'non-JSON response: HTTP ${r.statusCode}: '
        '${_truncate(r.body)}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw NativeException(
        'non-JSON response: HTTP ${r.statusCode}: ${_truncate(r.body)}',
      );
    }
    final Object? value = decoded['value'];
    if (value is Map && value['error'] != null) {
      throw NativeException(
        '${value['error']}: ${value['message'] ?? ''}'.trim(),
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
    final Map<String, Object?> caps = <String, Object?>{
      'platformName': 'iOS',
      'appium:automationName': 'XCUITest',
      'appium:udid': udid,
      'appium:app': app,
      'appium:forceSimulatorSoftwareKeyboardPresence': true,
      'appium:noReset': true,
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
    // XCUITest NATIVE_APP context sees the ASWebAuthenticationSession web
    // inputs (spike B1 retired).
    await _post('/session/$_sid/context', const <String, Object?>{
      'name': 'NATIVE_APP',
    });
  }

  @override
  Future<void> close() async {
    final String? sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try {
        await _client.delete(_u('/session/$sid'));
      } on Object {
        // best-effort: releasing the WDA session must never throw on teardown.
      }
    }
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Observation: poll /source -> parse XCUITest XML -> List<NativeNode>.
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
  // The XCUITest /source XML parser (m2-spec §5.3).
  // ---------------------------------------------------------------------------

  /// Map an `XCUIElementType*` `type` to the Flutter role vocabulary.
  static String _role(String type) {
    switch (type) {
      case 'XCUIElementTypeButton':
        return 'button';
      case 'XCUIElementTypeTextField':
      case 'XCUIElementTypeSecureTextField':
        return 'textfield';
      case 'XCUIElementTypeLink':
        return 'link';
      case 'XCUIElementTypeStaticText':
        return 'text';
      case 'XCUIElementTypeImage':
        return 'image';
      case 'XCUIElementTypeSwitch':
        return 'switch';
      default:
        return 'text';
    }
  }

  static int _toInt(String? v) =>
      v == null || v.isEmpty ? 0 : (double.tryParse(v) ?? 0).round();

  /// Parse a raw XCUITest `/source` XML document into the flattened, filtered
  /// list of [NativeNode]s in document order (m2-spec §5.3). Exposed for the
  /// parser unit test.
  @visibleForTesting
  List<NativeNode> parseSource(String xml) => _parseSource(xml);

  List<NativeNode> _parseSource(String xml) {
    final XmlDocument doc = XmlDocument.parse(xml);

    // Pass 1: collect every descendant element in document order, decide which
    // survive the container filter, and record per-type running counts so the
    // positional xpath index and name-uniqueness can be computed.
    final List<XmlElement> kept = <XmlElement>[];
    final Map<String, int> typeCount = <String, int>{}; // kept-only, per type.
    final Map<XmlElement, int> typeIndex = <XmlElement, int>{};
    final Map<String, int> nameCountByType = <String, int>{};

    for (final XmlElement el in doc.descendantElements) {
      final String type = el.getAttribute('type') ?? el.name.local;
      final String? name = _attr(el, 'name');
      final String? label = _attr(el, 'label');
      final String? value = _attr(el, 'value');
      final String role = _role(type);

      // Filter: drop pure structural containers — no name/label/value AND the
      // type maps to the default `text` role.
      final bool hasSignal = name != null || label != null || value != null;
      if (!hasSignal && role == 'text') continue;

      kept.add(el);
      final int idx = (typeCount[type] ?? 0) + 1;
      typeCount[type] = idx;
      typeIndex[el] = idx;
      if (name != null) {
        nameCountByType['$type $name'] =
            (nameCountByType['$type $name'] ?? 0) + 1;
      }
    }

    // Pass 2: materialize NativeNodes with dense document-order ids.
    final List<NativeNode> out = <NativeNode>[];
    int id = 0;
    for (final XmlElement el in kept) {
      final String type = el.getAttribute('type') ?? el.name.local;
      final String? name = _attr(el, 'name');
      final String? label = _attr(el, 'label');
      final String? value = _attr(el, 'value');
      final String role = _role(type);

      final int x = _toInt(el.getAttribute('x'));
      final int y = _toInt(el.getAttribute('y'));
      final int w = _toInt(el.getAttribute('width'));
      final int h = _toInt(el.getAttribute('height'));

      out.add(
        NativeNode(
          id: ++id,
          role: role,
          label: (label != null && label.isNotEmpty) ? label : name,
          value: value,
          rect: <int>[x, y, x + w, y + h],
          a11yId: name,
          xpath: _xpathFor(el, type, name, typeIndex, nameCountByType),
        ),
      );
    }
    return out;
  }

  /// Read an attribute, normalizing empty strings to null.
  static String? _attr(XmlElement el, String key) {
    final String? v = el.getAttribute(key);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Deterministic xpath synthesis (m2-spec §5.3 step 12): prefer a unique
  /// `[@name=…]` xpath; otherwise a positional `(//XCUIElementType<T>)[n]`
  /// where `n` is the 1-based document-order index among kept nodes of type T.
  static String _xpathFor(
    XmlElement el,
    String type,
    String? name,
    Map<XmlElement, int> typeIndex,
    Map<String, int> nameCountByType,
  ) {
    if (name != null && (nameCountByType['$type $name'] ?? 0) == 1) {
      return "//$type[@name='$name']";
    }
    return '(//$type)[${typeIndex[el]}]';
  }

  // ---------------------------------------------------------------------------
  // Resolution: the 4-tier selector chain (m2-spec §5.4).
  // ---------------------------------------------------------------------------

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) async {
    // Tier 1: a11y-id.
    if (selector.a11yId != null) {
      final String? eid = await _find('accessibility id', selector.a11yId!);
      if (eid != null) return NativeTarget(elementId: eid, via: 'a11y-id');
    }

    // Tier 2: label -> the matched cached node's a11yId / xpath / synthesized
    // positional xpath. Note _parseSource ALWAYS populates node.xpath (a unique
    // `[@name=…]` or a positional `(//Type)[n]`), so the spec's third
    // "synthesized positional" fallback is subsumed by the node.xpath branch
    // below; on a total miss the chain still falls through to tier-4 rect-center.
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

    // Tier 3: explicit xpath (load-bearing for anonymous Auth0 fields).
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
    await _post('/session/$_sid/element/$eid/value', <String, Object?>{
      'text': text,
    });
    // FN3: `masked` is element-TYPE-derived (a SecureTextField), NOT
    // `readback != text` — the latter false-positives on OS normalization.
    final bool masked = await _isSecureField(eid);
    final String readback = await _readValue(eid);
    // Per-platform keyboard dismiss, INSIDE the backend (kept off the seam).
    await _dismissKeyboard();
    return (readback: readback, masked: masked);
  }

  /// FN4: iOS reads `attribute/value`; Android reads `attribute/text`.
  Future<String> _readValue(String eid) async {
    final String attr = _ios ? 'value' : 'text';
    final Map<String, Object?> j = await _get(
      '/session/$_sid/element/$eid/attribute/$attr',
    );
    return (j['value'] ?? '').toString();
  }

  /// True iff the resolved element is an `XCUIElementTypeSecureTextField`
  /// (iOS). Reads the explicit element TYPE via `attribute/type` — NOT the
  /// W3C tag-name (`/element/{id}/name`) route, which on appium-xcuitest can
  /// return the accessibility name rather than the class: the Auth0 password
  /// field's `name` is literally "Password", so the `/name` route would make
  /// `masked` always false on a live drive (breaks FN3 / AC9 / AC18). The
  /// element TYPE is what drives the masked flag.
  Future<bool> _isSecureField(String eid) async {
    if (!_ios) return false;
    try {
      final Map<String, Object?> j = await _get(
        '/session/$_sid/element/$eid/attribute/type',
      );
      final String type = (j['value'] ?? '').toString();
      return type == 'XCUIElementTypeSecureTextField';
    } on NativeException {
      return false;
    }
  }

  /// Per-platform keyboard dismiss. iOS 26 has no "Done" key (no-op); older iOS
  /// taps "Done" when present; Android backs out. Non-fatal (B6) — a dismiss
  /// failure must never fail the type.
  Future<void> _dismissKeyboard() async {
    try {
      if (!_ios) {
        await _post('/session/$_sid/back', const <String, Object?>{});
        return;
      }
      if (osVersion.contains('26')) return; // iOS 26 has no Done key
      final String? done = await _find(
        'accessibility id',
        'Done',
        timeout: const Duration(seconds: 2),
      );
      if (done != null) {
        await _post(
          '/session/$_sid/element/$done/click',
          const <String, Object?>{},
        );
      }
    } on Object {
      // Non-fatal: dismiss is best-effort (may 404 on UIA2).
    }
  }

  @override
  Future<void> press(String key) async {
    switch (key) {
      case 'consent_accept':
        // iOS-only: the ASWebAuthenticationSession consent is a separate
        // SpringBoard alert (NOT in /source) — accept via the W3C endpoint.
        await _post('/session/$_sid/alert/accept', const <String, Object?>{});
        return;
      case 'enter':
      case 'return':
      case 'done':
        // Inject a newline keystroke into the active element.
        await _post('/session/$_sid/keys', <String, Object?>{
          'value': <String>['\n'],
        });
        return;
      case 'back':
        if (_ios) throw NativeException('unknown press key: $key');
        await _post('/session/$_sid/back', const <String, Object?>{});
        return;
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
