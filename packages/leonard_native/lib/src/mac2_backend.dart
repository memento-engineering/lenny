/// `Mac2Backend` — Appium W3C WebDriver using the mac2 driver.
///
/// The backend attaches to an already-running macOS application by bundle ID.
/// It never starts Appium, Xcode, an application, or a direct Accessibility
/// process. All WebDriver latency and `/source` polling stays behind this seam
/// so `NativeExtension.buildPerception()` remains a synchronous cached read.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import 'appium_capabilities.dart';
import 'native_backend.dart';
import 'native_snapshot.dart';

const String _w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// Drives a running macOS application through an Appium mac2 session.
class Mac2Backend implements NativeBackend {
  /// Creates a bundle-targeted backend against [server].
  ///
  /// The Appium server and [bundleId] application must already be running.
  /// [connect] uses `skipAppKill`, so [close] deletes only the WebDriver
  /// session and leaves the application running.
  Mac2Backend({
    Uri? server,
    required this.bundleId,
    this.pollInterval = const Duration(seconds: 1),
    http.Client? client,
  }) : server = server ?? Uri.parse('http://127.0.0.1:4723'),
       _client = client ?? http.Client() {
    if (bundleId.trim().isEmpty) {
      throw ArgumentError.value(
        bundleId,
        'bundleId',
        'Mac2 attach requires a non-empty bundleId',
      );
    }
  }

  /// The Appium server URL.
  final Uri server;

  /// The already-running application selected for the session.
  final String bundleId;

  /// Fixed platform tag emitted on every [NativeSnapshot].
  final String platform = 'darwin';

  /// The watcher poll cadence.
  final Duration pollInterval;

  final http.Client _client;
  String? _sessionId;

  Uri _u(String path) => server.resolve(path);

  String get _sid =>
      _sessionId ?? (throw NativeException('no session: call connect() first'));

  Future<Map<String, Object?>> _post(String path, Object body) async {
    final http.Response response = await _client.post(
      _u(path),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    return _unwrap(response);
  }

  Future<Map<String, Object?>> _get(String path) async {
    final http.Response response = await _client.get(_u(path));
    return _unwrap(response);
  }

  Map<String, Object?> _unwrap(http.Response response) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw NativeException(
        'non-JSON response: HTTP ${response.statusCode}: '
        '${_truncate(response.body)}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw NativeException(
        'non-JSON response: HTTP ${response.statusCode}: '
        '${_truncate(response.body)}',
      );
    }
    final Object? value = decoded['value'];
    if (value is Map && value['error'] != null) {
      throw NativeException(
        '${value['error']}: ${value['message'] ?? ''}'.trim(),
        code: value['error'].toString(),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NativeException(
        'HTTP ${response.statusCode}: ${_truncate(response.body)}',
      );
    }
    return decoded;
  }

  static String _truncate(String value) =>
      value.length <= 400 ? value : '${value.substring(0, 400)}…';

  @override
  Future<void> connect({
    Map<String, Object?> extraCapabilities = const <String, Object?>{},
  }) async {
    final Map<String, Object?> capabilities = mac2AttachCapabilities(
      bundleId: bundleId,
      extraCapabilities: extraCapabilities,
    );
    if (_sessionId != null) return;

    final Map<String, Object?> response = await _post(
      '/session',
      <String, Object?>{
        'capabilities': <String, Object?>{
          'alwaysMatch': capabilities,
          'firstMatch': <Object?>[<String, Object?>{}],
        },
      },
    );
    final Object? value = response['value'];
    final Object? nestedSessionId = value is Map ? value['sessionId'] : null;
    final Object? sessionId = nestedSessionId ?? response['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw NativeException('session open returned no sessionId');
    }
    _sessionId = sessionId;
  }

  @override
  Future<void> close() async {
    final String? sessionId = _sessionId;
    _sessionId = null;
    if (sessionId != null) {
      try {
        await _client.delete(_u('/session/$sessionId'));
      } on Object {
        // Best effort: session teardown must not replace the caller's result.
      }
    }
    _client.close();
  }

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
    final Map<String, Object?> response = await _get('/session/$_sid/source');
    final String source = (response['value'] ?? '').toString();
    return NativeSnapshot(platform: platform, nodes: _parseSource(source));
  }

  /// Parses mac2 XCTest XML into canonical nodes in document order.
  @visibleForTesting
  List<NativeNode> parseSource(String xml) => _parseSource(xml);

  List<NativeNode> _parseSource(String xml) {
    final XmlDocument document = XmlDocument.parse(xml);
    final List<XmlElement> kept = <XmlElement>[];
    final Map<String, int> typeCount = <String, int>{};
    final Map<XmlElement, int> typeIndex = <XmlElement, int>{};
    final Map<String, int> identifierCountByType = <String, int>{};

    for (final XmlElement element in document.descendantElements) {
      final String type = element.getAttribute('type') ?? element.name.local;
      final String? identifier = _attr(element, 'identifier');
      final String? label = _attr(element, 'label');
      final String? title = _attr(element, 'title');
      final String? value = _attr(element, 'value');
      final String role = _role(type);
      final bool hasSignal =
          identifier != null || label != null || title != null || value != null;

      if (!hasSignal && role == 'text') continue;

      kept.add(element);
      final int index = (typeCount[type] ?? 0) + 1;
      typeCount[type] = index;
      typeIndex[element] = index;
      if (identifier != null) {
        final String key = '$type\u0000$identifier';
        identifierCountByType[key] = (identifierCountByType[key] ?? 0) + 1;
      }
    }

    final List<NativeNode> nodes = <NativeNode>[];
    for (final XmlElement element in kept) {
      final String type = element.getAttribute('type') ?? element.name.local;
      final String? identifier = _attr(element, 'identifier');
      final String? label = _attr(element, 'label');
      final String? title = _attr(element, 'title');
      final int x = _toInt(element.getAttribute('x'));
      final int y = _toInt(element.getAttribute('y'));
      final int width = _toInt(element.getAttribute('width'));
      final int height = _toInt(element.getAttribute('height'));

      nodes.add(
        NativeNode(
          id: nodes.length + 1,
          role: _role(type),
          label: label ?? title ?? identifier,
          value: _attr(element, 'value'),
          rect: <int>[x, y, x + width, y + height],
          a11yId: identifier,
          xpath: _xpathFor(
            element,
            type,
            identifier,
            typeIndex,
            identifierCountByType,
          ),
          platformType: type,
          depth: element.ancestorElements.length,
        ),
      );
    }
    return nodes;
  }

  static String _role(String type) {
    final String name = type.startsWith('XCUIElementType')
        ? type.substring('XCUIElementType'.length)
        : type;
    return switch (name) {
      'Button' => 'button',
      'TextField' || 'SecureTextField' || 'TextView' => 'textfield',
      'Link' => 'link',
      'StaticText' => 'text',
      'Image' => 'image',
      'CheckBox' => 'checkbox',
      'Switch' => 'switch',
      'Slider' => 'slider',
      _ => 'text',
    };
  }

  static String? _attr(XmlElement element, String key) {
    final String? value = element.getAttribute(key);
    return value == null || value.isEmpty ? null : value;
  }

  static int _toInt(String? value) => value == null || value.isEmpty
      ? 0
      : (double.tryParse(value) ?? 0).round();

  static String _xpathFor(
    XmlElement element,
    String type,
    String? identifier,
    Map<XmlElement, int> typeIndex,
    Map<String, int> identifierCountByType,
  ) {
    if (identifier != null &&
        (identifierCountByType['$type\u0000$identifier'] ?? 0) == 1) {
      return '//$type[@identifier=${xpathLiteral(identifier)}]';
    }
    return '(//$type)[${typeIndex[element]}]';
  }

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) async {
    if (selector.a11yId != null) {
      final String? elementId = await _find(
        'accessibility id',
        selector.a11yId!,
      );
      if (elementId != null) {
        return NativeTarget(elementId: elementId, via: 'a11y-id');
      }
    }

    if (selector.label != null) {
      final NativeNode? node = _matchLabel(cached, selector.label!);
      if (node != null) {
        String? elementId;
        if (node.a11yId != null && node.a11yId!.isNotEmpty) {
          elementId = await _find('accessibility id', node.a11yId!);
        } else if (node.xpath != null && node.xpath!.isNotEmpty) {
          elementId = await _find('xpath', node.xpath!);
        }
        if (elementId != null) {
          return NativeTarget(elementId: elementId, via: 'label');
        }
      }
    }

    if (selector.xpath != null) {
      final String? elementId = await _find('xpath', selector.xpath!);
      if (elementId != null) {
        return NativeTarget(elementId: elementId, via: 'xpath');
      }
    }

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
    for (final NativeNode node in cached.nodes) {
      if (node.label == label) return node;
    }
    return null;
  }

  List<int>? _cachedRect(NativeSnapshot? cached, NativeSelector selector) {
    if (selector.label == null) return null;
    return _matchLabel(cached, selector.label!)?.rect;
  }

  Future<String?> _find(
    String strategy,
    String value, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final DateTime end = DateTime.now().add(timeout);
    while (true) {
      try {
        final Map<String, Object?> response = await _post(
          '/session/$_sid/element',
          <String, Object?>{'using': strategy, 'value': value},
        );
        final Object? result = response['value'];
        if (result is Map) {
          final Object? elementId =
              result[_w3cElementKey] ??
              (result.isEmpty ? null : result.values.first);
          if (elementId is String) return elementId;
        }
        return null;
      } on NativeException {
        if (!DateTime.now().isBefore(end)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  @override
  Future<void> tap(NativeTarget target) async {
    if (target.elementId != null) {
      await _post(
        '/session/$_sid/element/${target.elementId}/click',
        const <String, Object?>{},
      );
      return;
    }
    final ({int x, int y})? point = target.point;
    if (point == null) {
      throw NativeException('tap: target has neither elementId nor point');
    }
    await _post(
      '/session/$_sid/actions',
      _mouseActions(<Object?>[
        <String, Object?>{
          'type': 'pointerMove',
          'duration': 0,
          'x': point.x,
          'y': point.y,
        },
        <String, Object?>{'type': 'pointerDown', 'button': 0},
        <String, Object?>{'type': 'pause', 'duration': 50},
        <String, Object?>{'type': 'pointerUp', 'button': 0},
      ]),
    );
  }

  @override
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  ) async {
    final String? elementId = target.elementId;
    if (elementId == null) {
      throw NativeException('enter_text requires a resolved element');
    }
    await _post(
      '/session/$_sid/element/$elementId/clear',
      const <String, Object?>{},
    );
    await _post('/session/$_sid/element/$elementId/value', <String, Object?>{
      'text': text,
    });
    final bool masked = await _isSecureField(elementId);
    final String readback = await _readValue(elementId);
    return (readback: readback, masked: masked);
  }

  Future<String> _readValue(String elementId) async {
    final Map<String, Object?> response = await _get(
      '/session/$_sid/element/$elementId/attribute/value',
    );
    return (response['value'] ?? '').toString();
  }

  Future<bool> _isSecureField(String elementId) async {
    try {
      final Map<String, Object?> response = await _get(
        '/session/$_sid/element/$elementId/attribute/amType',
      );
      return response['value'] == 'XCUIElementTypeSecureTextField';
    } on NativeException {
      return false;
    }
  }

  @override
  Future<void> press(String key) async {
    switch (key) {
      case 'enter':
      case 'return':
      case 'done':
        await _post('/session/$_sid/execute/sync', <String, Object?>{
          'script': 'macos: keys',
          'args': <Object?>[
            <String, Object?>{
              'keys': <String>['XCUIKeyboardKeyReturn'],
            },
          ],
        });
        return;
      default:
        throw NativeException('unknown press key: $key');
    }
  }

  @override
  Future<void> swipe(NativeSwipe gesture) async {
    await _post(
      '/session/$_sid/actions',
      _mouseActions(<Object?>[
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
      ]),
    );
  }

  static Map<String, Object?> _mouseActions(List<Object?> actions) =>
      <String, Object?>{
        'actions': <Object?>[
          <String, Object?>{
            'type': 'pointer',
            'id': 'mouse1',
            'parameters': <String, Object?>{'pointerType': 'mouse'},
            'actions': actions,
          },
        ],
      };
}
