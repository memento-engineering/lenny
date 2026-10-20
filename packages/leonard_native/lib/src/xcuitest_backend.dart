/// `XcuiTestBackend` — Appium W3C WebDriver using the XCUITest driver.
///
/// Verified against Appium 3.5.2 + appium-xcuitest-driver 11.12.2, Xcode 26.5,
/// iOS 26 sim. All device latency (WebDriver round-trips, `/source` polling)
/// lives here so the extension's `buildPerception()` stays synchronous — the
/// pull-free build invariant.
///
/// Hardening applied (m2-spec §5.5): B5 (`_unwrap` honors HTTP status +
/// non-JSON bodies → [NativeException], never `FormatException`), FN3
/// (`enterText` masked flag is element-type-derived, NOT `readback != text`),
/// FN4 (`readValue` uses the fixed `attribute/value` route), B8 (launch mode
/// requires `udid`/`app`; attach mode requires `udid`/`appId`), plus the
/// skeleton-lift deletions: the
/// xpath-based "Continue" consent find is GONE — consent is
/// `POST /session/{id}/alert/accept` (`press('consent_accept')`), because the
/// SpringBoard consent is not in `/source`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import 'appium_capabilities.dart';
import 'appium_endpoint.dart';
import 'native_backend.dart';
import 'native_snapshot.dart';

/// The W3C element key returned by every successful `find`.
const String _w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// Drives a native iOS app over a local Appium server (W3C WebDriver +
/// XCUITest).
class XcuiTestBackend implements NativeBackend {
  /// Constructs an install-and-launch backend targeting [udid] + [app] on
  /// [server] (default `http://127.0.0.1:4723`). The backend does NOT spawn
  /// Appium or boot the simulator — both must already be running. [platform]
  /// is fixed to `ios`.
  ///
  /// Tears off to [NativeLaunch], the same shape as
  /// `UiAutomator2Backend.new`.
  XcuiTestBackend({
    Uri? server,
    required this.udid,
    required String app,
    this.platformVersion,
    this.pollInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : // A typed parameter keeps null out of this public launch constructor.
       // ignore: prefer_initializing_formals
       app = app,
       appId = null,
       server = server ?? Uri.parse('http://127.0.0.1:4723'),
       _client = client ?? http.Client();

  /// Constructs a backend that attaches to the already-running [appId] (the
  /// bundle id) without installing, relaunching or activating it: the session
  /// sends `appium:autoLaunch: false`, as `UiAutomator2Backend.attach` does,
  /// so it observes whatever is on screen. [connect] fails loudly when the
  /// app is not running once the session is open; [activateApp] brings it to
  /// the foreground on request.
  ///
  /// Tears off to [NativeAttach], the same shape as
  /// `UiAutomator2Backend.attach`.
  XcuiTestBackend.attach({
    Uri? server,
    required this.udid,
    required String appId,
    this.platformVersion,
    this.pollInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : app = null,
       // A typed parameter keeps null out of this public attach constructor.
       // ignore: prefer_initializing_formals
       appId = appId,
       server = server ?? Uri.parse('http://127.0.0.1:4723'),
       _client = client ?? http.Client();

  /// The local Appium server URL.
  final Uri server;

  /// Fixed platform tag emitted on every [NativeSnapshot].
  final String platform = 'ios';

  /// The booted simulator udid.
  final String udid;

  /// Path installed and launched by the unnamed constructor; null in attach
  /// mode.
  final String? app;

  /// Bundle id of the running application selected by the attach constructor;
  /// null in launch mode.
  final String? appId;

  /// Optional iOS version requested from Appium (for example, `26.0`). When
  /// absent or empty, the session request omits the version capability and
  /// the version Appium reports for the session is used instead.
  final String? platformVersion;

  /// The iOS version Appium reported for the active session, or null before
  /// [connect] / after [close].
  String? _sessionPlatformVersion;

  /// The watcher poll cadence.
  final Duration pollInterval;

  final http.Client _client;

  /// The active W3C session id, or null before [connect] / after [close].
  String? _sessionId;

  /// The open W3C session id, or null before [connect] / after [close].
  ///
  /// For issuing a W3C or Appium request this backend does not wrap yet,
  /// against the same session, without a parallel transport.
  String? get sessionId => _sessionId;

  // ---------------------------------------------------------------------------
  // Transport (lifted from the skeleton WITH the B5 hardening).
  // ---------------------------------------------------------------------------

  Uri _u(String path) => appiumEndpoint(server, path);

  /// Throws [NativeException] (never `StateError`) when no session is open.
  String get _sid =>
      _sessionId ?? (throw NativeException('no session: call connect() first'));

  void _requireSession() {
    _sid;
  }

  Future<Map<String, Object?>> _post(String path, Object body) async {
    final http.Response r = await appiumSend(
      () => _client.post(
        _u(path),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return _unwrap(r);
  }

  Future<Map<String, Object?>> _get(String path) async {
    final http.Response r = await appiumSend(() => _client.get(_u(path)));
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
      // Kept symmetrical with UiAutomator2Backend._unwrap: both platforms
      // speak W3C, so both tag the code. The message text is unchanged.
      throw NativeException(
        redactCredentials(
          '${value['error']}: ${value['message'] ?? ''}'.trim(),
        ),
        code: value['error'].toString(),
      );
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw NativeException('HTTP ${r.statusCode}: ${_truncate(r.body)}');
    }
    return decoded;
  }

  static String _truncate(String s) =>
      redactCredentials(s.length <= 400 ? s : '${s.substring(0, 400)}…');

  // ---------------------------------------------------------------------------
  // Session lifecycle.
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect({
    Map<String, Object?> extraCapabilities = const <String, Object?>{},
  }) async {
    final Map<String, Object?> caps = mergeAppiumCapabilities(
      defaults: <String, Object?>{
        'platformName': 'iOS',
        'appium:automationName': 'XCUITest',
        'appium:udid': udid,
        if (_requestedPlatformVersion case final String version)
          'appium:platformVersion': version,
        if (app case final String app) 'appium:app': app,
        if (appId case final String appId) ...<String, Object?>{
          'appium:bundleId': appId,
          // Attach observes; it never activates or launches the app.
          'appium:autoLaunch': false,
        },
        'appium:forceSimulatorSoftwareKeyboardPresence': true,
        'appium:noReset': true,
      },
      extraCapabilities: extraCapabilities,
    );
    if (_sessionId != null) return; // idempotent
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
    // lenny#185: from here the session exists, so a failure must release it.
    // Callers rarely keep a backend whose connect() threw, and an Android
    // session (newCommandTimeout 0) would otherwise hold the device forever.
    try {
      final Object? returnedCapabilities = value is Map
          ? value['capabilities']
          : null;
      _sessionPlatformVersion = switch (returnedCapabilities) {
        {'platformVersion': final Object version} => version.toString(),
        {'appium:platformVersion': final Object version} => version.toString(),
        _ => _requestedPlatformVersion,
      };
      // XCUITest NATIVE_APP context sees the ASWebAuthenticationSession web
      // inputs.
      await _post('/session/$_sid/context', const <String, Object?>{
        'name': 'NATIVE_APP',
      });
      if (appId case final String appId) {
        await _requireAttachedAppRunning(appId);
      }
    } on Object {
      await _releaseSession();
      rethrow;
    }
  }

  String? get _requestedPlatformVersion =>
      platformVersion == null || platformVersion!.isEmpty
      ? null
      : platformVersion;

  /// Attach must find the app running, and must not disturb it. Attach sends
  /// `autoLaunch: false`, so a backgrounded app stays backgrounded and reports
  /// `queryAppState` 2 (suspended) or 3; both are running. Only a definite 0
  /// (not installed) or 1 (not running) fails; an unanswered probe is
  /// unknown, not a failure.
  ///
  /// A 1 has two causes: the app was never started, or, on Xcode 27, the
  /// simulator UI is DeviceHub, which XCUITest driver <= 11 does not
  /// recognise: it reboots the booted simulator on session create and the app
  /// is SIGTERMed.
  Future<void> _requireAttachedAppRunning(String appId) async {
    final Object? state;
    try {
      final Map<String, Object?> j = await _post(
        '/session/$_sid/execute/sync',
        <String, Object?>{
          'script': 'mobile: queryAppState',
          'args': <Object?>[
            <String, Object?>{'bundleId': appId},
          ],
        },
      );
      state = j['value'];
    } on NativeException catch (e) {
      // An unanswered probe is unknown; a dead transport is a failed connect.
      if (e.code == NativeException.transportErrorCode) rethrow;
      return;
    }
    if (state is int && state < 2) {
      throw NativeException(
        'attach to $appId: the app is not running after session create '
        '(queryAppState $state). Attach never starts it: launch it first, or '
        'construct XcuiTestBackend with app: to install and launch it. If it '
        'was running, on Xcode 27 the simulator UI is DeviceHub '
        '(com.apple.dt.Devices); Appium XCUITest driver 11.x or older does '
        'not recognise it, reboots the simulator and kills the app. Upgrade '
        'to XCUITest driver 12 or newer (appium driver update xcuitest).',
      );
    }
  }

  @override
  Future<void> close() async {
    await _releaseSession();
    _client.close();
  }

  /// Clears the session state and best-effort deletes the session, leaving
  /// the HTTP client open so [connect] can be retried.
  Future<void> _releaseSession() async {
    final String? sid = _sessionId;
    _sessionId = null;
    _sessionPlatformVersion = null;
    if (sid != null) {
      try {
        await _client.delete(_u('/session/$sid'));
      } on Object {
        // best-effort: releasing the WDA session must never throw on teardown.
      }
    }
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
        nameCountByType['$type\u0000$name'] =
            (nameCountByType['$type\u0000$name'] ?? 0) + 1;
      }
    }

    // Pass 2: materialize NativeNodes with dense document-order ids.
    final List<NativeNode> out = <NativeNode>[];
    final Map<XmlElement, int> ids = <XmlElement, int>{};
    int id = 0;
    for (final XmlElement el in kept) {
      // The nearest kept ancestor: ancestors precede descendants in document
      // order, so theirs are already assigned.
      int? parentId;
      for (final XmlElement ancestor in el.ancestorElements) {
        parentId = ids[ancestor];
        if (parentId != null) break;
      }
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
          // Flutter's vocabulary emits the negative, as Android's does; an
          // absent attribute is unknown, not enabled-false.
          state: el.getAttribute('enabled') == 'false'
              ? const <String>['disabled']
              : const <String>[],
          a11yId: name,
          xpath: _xpathFor(el, type, name, typeIndex, nameCountByType),
          platformType: type,
          depth: el.ancestorElements.length,
          parentId: parentId,
        ),
      );
      ids[el] = id;
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
    if (name != null && (nameCountByType['$type\u0000$name'] ?? 0) == 1) {
      return "//$type[@name='$name']";
    }
    return '(//$type)[${typeIndex[el]}]';
  }

  // ---------------------------------------------------------------------------
  // Resolution: the iOS 4-tier chain. resourceId is Android-only and is
  // deliberately skipped without synthesizing an id, predicate, or XPath.
  // ---------------------------------------------------------------------------

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached, {
    Duration findTimeout = NativeBackend.defaultFindTimeout,
  }) async {
    // Tier 1: a11y-id.
    if (selector.a11yId != null) {
      final String? eid = await _find(
        'accessibility id',
        selector.a11yId!,
        timeout: findTimeout,
      );
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
          eid = await _find(
            'accessibility id',
            node.a11yId!,
            timeout: findTimeout,
          );
        } else if (node.xpath != null && node.xpath!.isNotEmpty) {
          eid = await _find('xpath', node.xpath!, timeout: findTimeout);
        }
        if (eid != null) return NativeTarget(elementId: eid, via: 'label');
      }
    }

    // Tier 3: explicit xpath (load-bearing for anonymous Auth0 fields).
    if (selector.xpath != null) {
      final String? eid = await _find(
        'xpath',
        selector.xpath!,
        timeout: findTimeout,
      );
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

  @override
  Future<bool> isPresent(NativeSelector selector) async {
    final List<(String, String)> finds = <(String, String)>[
      if (selector.a11yId case final String id) ('accessibility id', id),
      if (selector.label case final String label)
        (
          'xpath',
          '//*[@label=${xpathLiteral(label)} or @name=${xpathLiteral(label)}]',
        ),
      if (selector.xpath case final String xpath) ('xpath', xpath),
    ];
    if (finds.isEmpty) {
      throw ArgumentError.value(
        selector,
        'selector',
        'isPresent needs a resource-id, a11y-id, label or xpath',
      );
    }
    for (final (String strategy, String value) in finds) {
      if (await _find(strategy, value, timeout: Duration.zero) != null) {
        return true;
      }
    }
    return false;
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
  /// element never appears within the window; a zero [timeout] is one request.
  Future<String?> _find(
    String strategy,
    String value, {
    Duration timeout = NativeBackend.defaultFindTimeout,
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
      } on NativeException catch (e) {
        // A miss retries; a dead transport fails now, as it always has.
        if (e.code == NativeException.transportErrorCode) rethrow;
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
    String text, {
    bool dismissKeyboard = true,
  }) async {
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
    // iOS keyboard dismiss, INSIDE the backend (kept off the seam).
    if (dismissKeyboard) await _dismissKeyboard();
    return (readback: readback, masked: masked);
  }

  /// FN4: XCUITest reads `attribute/value`.
  Future<String> _readValue(String eid) async {
    final Map<String, Object?> j = await _get(
      '/session/$_sid/element/$eid/attribute/value',
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

  /// iOS-only keyboard dismiss. iOS 26 has no "Done" key (no-op); older iOS
  /// taps "Done" when present. An unknown version is treated as iOS 26, the
  /// verified target. A dismiss failure must never fail the type.
  Future<void> _dismissKeyboard() async {
    try {
      final String version = _sessionPlatformVersion ?? '26';
      if (version.contains('26')) return; // iOS 26 has no Done key
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
      // Non-fatal: dismiss is best-effort.
    }
  }

  @override
  Future<void> press(String key) async {
    _requireSession();
    switch (key) {
      case 'consent_accept':
        // iOS-only: the ASWebAuthenticationSession consent is a separate
        // SpringBoard alert (NOT in /source) — accept via the W3C endpoint.
        await _post('/session/$_sid/alert/accept', const <String, Object?>{});
        return;
      case 'alert_dismiss':
        // iOS-only: dismiss a SpringBoard system alert (e.g. "Save Password?")
        // — a separate process NOT in /source, exactly parallel to
        // consent_accept. /alert/dismiss = the "Not Now" / cancel button. When
        // no alert is open the W3C endpoint returns a "no alert open" error,
        // which _unwrap surfaces as a NativeException (ok:false) — a non-fatal
        // no-op for an adaptive caller.
        await _post('/session/$_sid/alert/dismiss', const <String, Object?>{});
        return;
      case 'enter':
      case 'return':
      case 'done':
        // Inject a newline keystroke into the active element.
        await _post('/session/$_sid/keys', <String, Object?>{
          'value': <String>['\n'],
        });
        return;
      case 'permission_allow':
      case 'permission_deny':
        throw NativeException('unknown press key: $key (Android-only)');
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

  @override
  Future<String?> alertText() async {
    try {
      final Map<String, Object?> j = await _get('/session/$_sid/alert/text');
      return j['value']?.toString();
    } on NativeException catch (e) {
      // A SpringBoard alert is not in /source; W3C reports its absence as an
      // error, which here is the ordinary "no alert" answer.
      if (e.code == NativeException.noSuchAlertCode) return null;
      rethrow;
    }
  }

  @override
  Future<void> activateApp(String appId) async {
    await _post('/session/$_sid/execute/sync', <String, Object?>{
      'script': 'mobile: activateApp',
      'args': <Object?>[
        <String, Object?>{'bundleId': appId},
      ],
    });
  }

  @override
  Future<String?> readAttribute(NativeTarget target, String name) async {
    final String? eid = target.elementId;
    if (eid == null) {
      throw NativeException('readAttribute requires a resolved element');
    }
    final Map<String, Object?> j = await _get(
      '/session/$_sid/element/$eid/attribute/${Uri.encodeComponent(name)}',
    );
    return j['value']?.toString();
  }

  @override
  Future<String> rawSource() async {
    final Map<String, Object?> j = await _get('/session/$_sid/source');
    return (j['value'] ?? '').toString();
  }

  @override
  Future<bool> acceptAlertIfPresent() => _answerAlertIfPresent('accept');

  @override
  Future<bool> dismissAlertIfPresent() => _answerAlertIfPresent('dismiss');

  Future<bool> _answerAlertIfPresent(String verb) async {
    try {
      await _post('/session/$_sid/alert/$verb', const <String, Object?>{});
      return true;
    } on NativeException catch (e) {
      if (e.code == NativeException.noSuchAlertCode) return false;
      rethrow;
    }
  }
}
