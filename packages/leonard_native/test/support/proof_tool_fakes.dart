import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Computes the result for one process invocation recorded by a
/// [FakeProcessLedger].
///
/// Test responders should throw [StateError] for every invocation they do not
/// explicitly handle.
typedef FakeProcessResponder =
    ProcessResult Function(String executable, List<String> arguments);

/// An immutable process invocation captured by [FakeProcessLedger].
final class FakeProcessInvocation {
  const FakeProcessInvocation({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

/// Records injected process calls before forwarding them to a strict fake.
final class FakeProcessLedger {
  FakeProcessLedger(this._responder);

  final FakeProcessResponder _responder;
  final List<FakeProcessInvocation> _invocations = <FakeProcessInvocation>[];

  /// Every invocation in call order.
  List<FakeProcessInvocation> get invocations =>
      List<FakeProcessInvocation>.unmodifiable(_invocations);

  /// The number of recorded `adb shell pm clear` reset cycles.
  int get resetCycleCount =>
      _invocations.where((FakeProcessInvocation invocation) {
        return invocation.executable.split('/').last == 'adb' &&
            _containsSequence(invocation.arguments, const <String>[
              'shell',
              'pm',
              'clear',
            ]);
      }).length;

  /// A [Process.run]-compatible function that records before responding.
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final List<String> copiedArguments = List<String>.unmodifiable(arguments);
    _invocations.add(
      FakeProcessInvocation(executable: executable, arguments: copiedArguments),
    );
    return _responder(executable, copiedArguments);
  }

  static bool _containsSequence(List<String> values, List<String> sequence) {
    for (int start = 0; start <= values.length - sequence.length; start += 1) {
      if (values
          .skip(start)
          .take(sequence.length)
          .toList()
          .indexed
          .every(((int, String) entry) => entry.$2 == sequence[entry.$1])) {
        return true;
      }
    }
    return false;
  }
}

/// An immutable HTTP request captured by [FakeAppiumClientFactory].
final class FakeAppiumRequest {
  const FakeAppiumRequest({
    required this.method,
    required this.path,
    required this.body,
  });

  final String method;
  final String path;
  final String body;
}

/// Creates strict, stateful Appium clients for offline proof-tool tests.
///
/// Each client owns one independent permission-dialog session. The fake only
/// supports session creation, source reads, allow/deny element lookup and
/// clicks, and session deletion; every other request throws [StateError].
final class FakeAppiumClientFactory {
  FakeAppiumClientFactory({
    required this.visibleSource,
    required this.dismissedSource,
    Map<String, Object?> capabilities = const <String, Object?>{},
    this.allowResourceId =
        'com.android.permissioncontroller:id/permission_allow_button',
    this.denyResourceId =
        'com.android.permissioncontroller:id/permission_deny_button',
    bool permissionGranted = false,
  }) : capabilities = Map<String, Object?>.unmodifiable(capabilities),
       _permissionGranted = permissionGranted;

  static const String _elementKey = 'element-6066-11e4-a52e-4f735466cecf';

  final String visibleSource;
  final String dismissedSource;
  final Map<String, Object?> capabilities;
  final String allowResourceId;
  final String denyResourceId;
  final List<FakeAppiumRequest> _requests = <FakeAppiumRequest>[];
  final List<_FakeAppiumSession> _sessions = <_FakeAppiumSession>[];
  final List<String> _pressKeys = <String>[];
  bool _permissionGranted;

  /// Every Appium request in call order across all created clients.
  List<FakeAppiumRequest> get requests =>
      List<FakeAppiumRequest>.unmodifiable(_requests);

  /// The number of successfully created Appium sessions.
  int get sessionCount => _sessions.length;

  /// Permission actions inferred from completed session behavior.
  List<String> get pressKeys => List<String>.unmodifiable(_pressKeys);

  /// The permission state exposed to a fake `dumpsys package` process call.
  bool get permissionGranted => _permissionGranted;

  /// Models the permission reset performed before a new proof exercise.
  void resetPermission() {
    _permissionGranted = false;
  }

  /// Creates a fresh HTTP client that accepts one Appium session.
  http.Client call() {
    _FakeAppiumSession? clientSession;
    return MockClient((http.Request request) async {
      _requests.add(
        FakeAppiumRequest(
          method: request.method,
          path: request.url.path,
          body: request.body,
        ),
      );

      if (request.method == 'POST' && request.url.path == '/session') {
        if (clientSession != null) {
          throw StateError('Appium client opened more than one session');
        }
        final Object? body = _decodeBody(request);
        if (body is! Map || body['capabilities'] is! Map) {
          throw StateError('Unhandled Appium session body: ${request.body}');
        }
        final _FakeAppiumSession session = _FakeAppiumSession(
          id: 'fake-${_sessions.length + 1}',
        );
        _sessions.add(session);
        clientSession = session;
        return _response(<String, Object?>{
          'sessionId': session.id,
          'capabilities': capabilities,
        });
      }

      final _FakeAppiumSession session =
          clientSession ??
          (throw StateError(
            'Unhandled Appium request before session: '
            '${request.method} ${request.url.path}',
          ));
      if (session.closed) {
        throw StateError(
          'Unhandled Appium request after close: '
          '${request.method} ${request.url.path}',
        );
      }
      final String sessionPath = '/session/${session.id}';

      if (request.method == 'GET' &&
          request.url.path == '$sessionPath/source') {
        _requireEmptyBody(request);
        if (session.dialogVisible) session.visibleSourceReads += 1;
        return _response(
          session.dialogVisible ? visibleSource : dismissedSource,
        );
      }

      if (request.method == 'POST' &&
          request.url.path == '$sessionPath/element') {
        if (!session.dialogVisible) {
          throw StateError('Element lookup after permission dialog dismissal');
        }
        final Object? body = _decodeBody(request);
        if (body is! Map || body['using'] != 'id') {
          throw StateError('Unhandled Appium element body: ${request.body}');
        }
        final String? elementId = switch (body['value']) {
          final Object value when value == allowResourceId => session.allowId,
          final Object value when value == denyResourceId => session.denyId,
          _ => null,
        };
        if (elementId == null) {
          throw StateError('Unhandled Appium element body: ${request.body}');
        }
        return _response(<String, Object?>{_elementKey: elementId});
      }

      final String? clickedKey = switch (request.url.path) {
        final String path
            when path == '$sessionPath/element/${session.allowId}/click' =>
          'permission_allow',
        final String path
            when path == '$sessionPath/element/${session.denyId}/click' =>
          'permission_deny',
        _ => null,
      };
      if (request.method == 'POST' && clickedKey != null) {
        _requireJsonObjectBody(request);
        if (!session.dialogVisible || session.clickedKey != null) {
          throw StateError('Invalid permission click: $clickedKey');
        }
        session.clickedKey = clickedKey;
        session.dialogVisible = false;
        _permissionGranted = clickedKey == 'permission_allow';
        _pressKeys.add(clickedKey);
        return _response(null);
      }

      if (request.method == 'DELETE' && request.url.path == sessionPath) {
        _requireEmptyBody(request);
        session.closed = true;
        if (session.clickedKey == null &&
            session.dialogVisible &&
            session.visibleSourceReads > 1) {
          _pressKeys.add('dismiss_overlay');
        }
        return _response(null);
      }

      throw StateError(
        'Unhandled Appium request: ${request.method} ${request.url.path} '
        '${request.body}',
      );
    });
  }

  static Object? _decodeBody(http.Request request) {
    try {
      return jsonDecode(request.body);
    } on FormatException {
      throw StateError('Unhandled non-JSON Appium body: ${request.body}');
    }
  }

  static void _requireJsonObjectBody(http.Request request) {
    if (_decodeBody(request) is! Map) {
      throw StateError('Unhandled Appium body: ${request.body}');
    }
  }

  static void _requireEmptyBody(http.Request request) {
    if (request.body.isNotEmpty) {
      throw StateError('Unhandled Appium body: ${request.body}');
    }
  }

  static http.Response _response(Object? value) => http.Response(
    jsonEncode(<String, Object?>{'value': value}),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

final class _FakeAppiumSession {
  _FakeAppiumSession({required this.id});

  final String id;
  bool dialogVisible = true;
  bool closed = false;
  int visibleSourceReads = 0;
  String? clickedKey;

  String get allowId => '$id-allow';
  String get denyId => '$id-deny';
}
