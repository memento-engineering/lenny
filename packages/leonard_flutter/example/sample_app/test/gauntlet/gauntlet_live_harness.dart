import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

typedef GauntletDriver =
    Future<Map<String, Object?>> Function(
      GauntletDriveRequest request,
      LeonardDrive drive,
    );

class GauntletDriveRequest {
  const GauntletDriveRequest(this.uri, this.route, this.goal);

  final Uri uri;
  final String route;
  final String goal;
}

class LeonardDrive {
  const LeonardDrive(this.script, this.cwd, {this.run = Process.run});

  final String script;
  final String cwd;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  run;

  Future<Map<String, Object?>> observe(Uri uri) =>
      _call(<String>['observe', '--vm-uri', uri.toString()]);

  Future<Map<String, Object?>> invoke(
    Uri uri,
    String tool,
    Map<String, Object?> args,
  ) => _call(<String>[
    'invoke',
    '--vm-uri',
    uri.toString(),
    '--tool',
    tool,
    '--args',
    jsonEncode(args),
  ]);

  Future<Map<String, Object?>> screenshot(Uri uri, String out) =>
      _call(<String>['screenshot', '--vm-uri', uri.toString(), '--out', out]);

  Future<Map<String, Object?>> _call(List<String> args) async {
    final ProcessResult result = await run(
      Platform.resolvedExecutable,
      <String>['run', script, ...args],
      workingDirectory: cwd,
    );
    if (result.exitCode != 0) {
      throw StateError('leonard_drive failed: ${result.stderr}');
    }
    final Object? value = jsonDecode(result.stdout.toString().trim());
    if (value is! Map) {
      throw StateError('leonard_drive returned non-object');
    }
    return value.cast<String, Object?>();
  }
}

abstract interface class GauntletOracleReader {
  Future<Map<String, Object?>> read(Uri uri);
}

class VmServiceGauntletOracleReader implements GauntletOracleReader {
  const VmServiceGauntletOracleReader();

  @override
  Future<Map<String, Object?>> read(Uri uri) async {
    final VmService service = await vmServiceConnectUri(uri.toString());
    try {
      final String? isolateId =
          (await service.getVM()).isolates?.firstOrNull?.id;
      if (isolateId == null) {
        throw StateError('oracle target has no isolate');
      }
      final Response response = await service.callServiceExtension(
        'ext.gauntlet.oracle',
        isolateId: isolateId,
        args: const <String, dynamic>{'op': 'get'},
      );
      return Map<String, Object?>.from(
        response.json ?? const <String, Object?>{},
      );
    } finally {
      await service.dispose();
    }
  }
}

class GauntletLiveHarness {
  const GauntletLiveHarness(
    this.drive, {
    this.reader = const VmServiceGauntletOracleReader(),
  });

  final LeonardDrive drive;
  final GauntletOracleReader reader;

  static const Set<String> interactionIds = <String>{
    'settle/decorative-motion',
    'settle/transient-toast',
    'control/label-lie',
    'control/expand-to-reach',
    'control/modal-trap',
    'control/lazy-offscreen',
    'control/custom-paint-control',
    'vision/object-id',
  };

  Future<void> run({
    required Uri uri,
    required String route,
    required String goal,
    required GauntletDriver driver,
  }) async {
    if (!route.startsWith('/g/')) {
      throw ArgumentError.value(route, 'route', 'must start with /g/');
    }
    final String id = route.substring(3);
    final Map<String, Object?> reported = await driver(
      GauntletDriveRequest(uri, route, goal),
      drive,
    );
    final Map<String, Object?> envelope = await reader.read(uri);
    if (envelope['active'] != true || envelope['oracle'] is! Map) {
      throw StateError('$id: oracle inactive or malformed');
    }
    final Map<String, Object?> oracle = Map<String, Object?>.from(
      envelope['oracle']! as Map,
    );
    if (oracle['scenario_id'] != id) {
      throw StateError('$id: oracle scenario mismatch');
    }
    if (interactionIds.contains(id)) {
      if (oracle['goal_reached'] != true) {
        throw StateError('$id: goal_reached is false');
      }
      return;
    }

    final Object? rawExpected = oracle['expected'];
    if (rawExpected is! Map || rawExpected.isEmpty) {
      throw StateError('$id: catalog defect; expected is empty');
    }
    for (final MapEntry<Object?, Object?> entry in rawExpected.entries) {
      final String key = entry.key.toString();
      if (!goal.toLowerCase().contains(key.toLowerCase())) {
        throw StateError('$id: goal does not name expected key $key');
      }
      if (!reported.containsKey(key) || !_matches(entry.value, reported[key])) {
        throw StateError('$id: answer mismatch for $key');
      }
    }
  }

  static bool _matches(Object? expected, Object? reported) {
    if (expected is String && reported is String) {
      return expected.trim().toLowerCase() == reported.trim().toLowerCase();
    }
    if (expected is num && reported is num) {
      return expected.toDouble() == reported.toDouble();
    }
    return expected == reported;
  }
}
