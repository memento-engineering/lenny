/// Deterministic device, application, and provider preflight.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'e2e_service.dart';
import 'e2e_session.dart';

/// Default swift-infer model used when no request or environment id is set.
const String kDefaultQwenModelId = 'qwen3.6-35b-a3b-8bit';

/// One device decoded from `flutter devices --machine`.
class FlutterDevice {
  /// Creates a Flutter device value.
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.connectionInterface,
    required this.isSupported,
  });

  /// Decodes one Flutter machine-output entry.
  factory FlutterDevice.fromJson(Map<String, Object?> json) => FlutterDevice(
    id: json['id'] is String ? json['id']! as String : '',
    name: json['name'] is String ? json['name']! as String : '',
    targetPlatform: json['targetPlatform'] is String
        ? json['targetPlatform']! as String
        : '',
    connectionInterface: json['connectionInterface'] is String
        ? json['connectionInterface']! as String
        : '',
    isSupported: json['isSupported'] is bool
        ? json['isSupported']! as bool
        : true,
  );

  /// Stable Flutter device id.
  final String id;

  /// Human-readable device name.
  final String name;

  /// Flutter target platform string.
  final String targetPlatform;

  /// Flutter connection interface (`attached` or `wireless`).
  final String connectionInterface;

  /// Whether Flutter reports this device as supported.
  final bool isSupported;

  /// Whether this is an iOS target.
  bool get isIos => targetPlatform.toLowerCase().startsWith('ios');

  /// Whether this target uses a wireless connection.
  bool get isWireless => connectionInterface.toLowerCase() == 'wireless';
}

/// Cleared inputs returned by preflight.
class E2ePreflight {
  /// Creates a cleared preflight value.
  const E2ePreflight({required this.device, required this.modelId});

  /// Selected wired iOS device.
  final FlutterDevice device;

  /// Exact model id when the request or provider resolved one.
  final String? modelId;
}

/// Runs all deterministic checks before a Flutter process starts.
Future<E2ePreflight> performE2ePreflight(
  E2eRuntime runtime,
  E2eSessionRequest request,
) async {
  if (request.goal.trim().isEmpty ||
      request.extensions.any((String value) => value.trim().isEmpty) ||
      request.cliPrefix.isEmpty ||
      request.cliPrefix.any((String value) => value.trim().isEmpty)) {
    throw const E2ePhaseFailure(
      E2eFailureCode.invalidRequest,
      'e2e preflight refused: goal, extensions, and CLI must be non-empty',
    );
  }
  if (!p.isAbsolute(request.appDir) ||
      !await runtime.directoryExists(request.appDir) ||
      !await runtime.fileExists(p.join(request.appDir, 'pubspec.yaml')) ||
      !await runtime.directoryExists(p.join(request.appDir, 'ios'))) {
    throw E2ePhaseFailure(
      E2eFailureCode.appDirectory,
      'e2e preflight refused: ${request.appDir} is not an absolute Flutter '
      'application directory containing pubspec.yaml and ios/',
    );
  }

  final E2eProcessResult discovery;
  try {
    discovery = await runtime.runProcess('flutter', const <String>[
      'devices',
      '--machine',
    ]);
  } on Object catch (error) {
    throw E2ePhaseFailure(
      E2eFailureCode.deviceDiscovery,
      'e2e preflight refused: flutter device discovery failed: $error',
    );
  }
  if (discovery.exitCode != 0) {
    throw E2ePhaseFailure(
      E2eFailureCode.deviceDiscovery,
      'e2e preflight refused: flutter devices exited '
      '${discovery.exitCode}',
    );
  }

  final List<FlutterDevice> devices;
  try {
    final Object? decoded = jsonDecode(discovery.stdout);
    if (decoded is! List) throw const FormatException('expected a JSON list');
    devices = <FlutterDevice>[
      for (final Object? entry in decoded)
        if (entry is Map)
          FlutterDevice.fromJson(Map<String, Object?>.from(entry)),
    ];
  } on Object catch (error) {
    throw E2ePhaseFailure(
      E2eFailureCode.deviceDiscovery,
      'e2e preflight refused: malformed flutter device JSON: $error',
    );
  }

  final String requestedId = request.device?.trim() ?? '';
  final FlutterDevice selected;
  if (requestedId.isNotEmpty) {
    final List<FlutterDevice> matches = devices
        .where((FlutterDevice device) => device.id == requestedId)
        .toList(growable: false);
    if (matches.length != 1 ||
        !matches.single.isIos ||
        !matches.single.isSupported) {
      throw E2ePhaseFailure(
        E2eFailureCode.deviceSelection,
        'e2e preflight refused: $requestedId is not one supported iOS device',
      );
    }
    selected = matches.single;
  } else {
    final List<FlutterDevice> eligible = devices
        .where(
          (FlutterDevice device) =>
              device.isIos && device.isSupported && !device.isWireless,
        )
        .toList(growable: false);
    if (eligible.length != 1) {
      throw E2ePhaseFailure(
        E2eFailureCode.deviceSelection,
        'e2e preflight refused: expected exactly one supported wired iOS '
        'device, found ${eligible.length}',
      );
    }
    selected = eligible.single;
  }
  if (selected.isWireless) {
    throw E2ePhaseFailure(
      E2eFailureCode.wirelessDevice,
      'e2e preflight refused: ${selected.id} is wireless',
    );
  }

  String? resolvedModelId = request.modelId?.trim();
  if (resolvedModelId?.isEmpty ?? false) resolvedModelId = null;
  switch (request.model) {
    case E2eModel.claude:
      _requireEnvironment(runtime, 'ANTHROPIC_API_KEY');
    case E2eModel.openai:
      _requireEnvironment(runtime, 'OPENAI_API_KEY');
    case E2eModel.qwenMlx:
      final String endpoint = _requireEnvironment(
        runtime,
        'SWIFT_INFER_ENDPOINT',
      );
      final String token = _requireEnvironment(
        runtime,
        'SWIFT_INFER_AGENT_TOKEN',
      );
      resolvedModelId ??=
          runtime.environment('SWIFT_INFER_MODEL')?.trim().isNotEmpty == true
          ? runtime.environment('SWIFT_INFER_MODEL')!.trim()
          : kDefaultQwenModelId;
      try {
        final Uri base = Uri.parse(endpoint);
        final Uri catalogUri = base.replace(
          path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/v1/models',
        );
        final E2eHttpResponse response = await runtime.get(
          catalogUri,
          headers: <String, String>{'Authorization': 'Bearer $token'},
        );
        if (response.statusCode != 200) {
          throw StateError('HTTP ${response.statusCode}');
        }
        final Object? decoded = jsonDecode(response.body);
        final Object? data = decoded is Map ? decoded['data'] : null;
        if (data is! List) throw const FormatException('missing data list');
        final Set<String> ids = <String>{
          for (final Object? item in data)
            if (item is Map && item['id'] is String) item['id']! as String,
        };
        if (!ids.contains(resolvedModelId)) {
          throw StateError('$resolvedModelId is not served');
        }
      } on Object catch (error) {
        throw E2ePhaseFailure(
          E2eFailureCode.modelCatalog,
          'e2e preflight refused: swift-infer model catalog did not clear '
          '$resolvedModelId: $error',
        );
      }
  }
  return E2ePreflight(device: selected, modelId: resolvedModelId);
}

String _requireEnvironment(E2eRuntime runtime, String name) {
  final String value = runtime.environment(name)?.trim() ?? '';
  if (value.isEmpty) {
    throw E2ePhaseFailure(
      E2eFailureCode.missingEnvironment,
      'e2e preflight refused: $name is unset',
    );
  }
  return value;
}
