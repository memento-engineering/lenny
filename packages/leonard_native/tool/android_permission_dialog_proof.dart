import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_native/leonard_native.dart';

const String adb =
    '/opt/homebrew/share/android-commandlinetools/platform-tools/adb';
const String serial = 'RF8RB21P6LN';
const String packageName = 'com.epi';
const String permission = 'android.permission.POST_NOTIFICATIONS';
final Uri appium = Uri(scheme: 'http', host: '127.0.0.1', port: 4723);
const List<List<String>> trigger = <List<String>>[
  <String>['shell', 'am', 'force-stop', packageName],
  <String>['shell', 'monkey', '-p', packageName, '1'],
];

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef CommandEvidence = ({
  List<String> argv,
  int exitCode,
  String stdout,
  String stderr,
});
typedef ActionEvidence = ({
  String key,
  String result,
  bool dialogBefore,
  bool dialogAfter,
  bool grantedAfter,
  bool backPosted,
});

final class RequestEvidence {
  const RequestEvidence(this.method, this.path, this.status, this.value);
  final String method;
  final String path;
  final int status;
  final Object? value;

  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'path': path,
    'status': status,
    'value': value,
  };
}

final class RecordingClient extends http.BaseClient {
  RecordingClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;
  final List<RequestEvidence> records = <RequestEvidence>[];
  List<String> get hits => records
      .map((RequestEvidence value) => '${value.method} ${value.path}')
      .toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response = await _inner.send(request);
    final List<int> bytes = await response.stream.toBytes();
    Object? value;
    try {
      value = (jsonDecode(utf8.decode(bytes)) as Map<String, Object?>)['value'];
    } on Object {
      value = null;
    }
    records.add(
      RequestEvidence(
        request.method,
        request.url.path,
        response.statusCode,
        value,
      ),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

final class AndroidPermissionDialogProof {
  AndroidPermissionDialogProof({
    this.runProcess = Process.run,
    http.Client Function()? clientFactory,
    Directory? packageRoot,
  }) : clientFactory = clientFactory ?? http.Client.new,
       packageRoot = packageRoot ?? Directory.current;

  final ProcessRunner runProcess;
  final http.Client Function() clientFactory;
  final Directory packageRoot;

  File get fixture => File(
    '${packageRoot.path}/test/fixtures/android_permission_dialog_source.xml',
  );
  File get receipt => File(
    '${packageRoot.path}/test/fixtures/android_permission_dialog_proof.json',
  );

  Future<void> requireDeviceAvailable() async {
    final ProcessResult result = await runProcess('bd', <String>[
      'list',
      '--id=lenny-91vu',
      '--status=open',
      '--json',
    ]);
    List<Object?> rows = <Object?>[];
    try {
      rows = jsonDecode(result.stdout.toString()) as List<Object?>;
    } on Object {
      // Report malformed output through the same fail-closed error below.
    }
    if (result.exitCode != 0 || rows.length != 1) {
      throw StateError(
        'RF8RB21P6LN unavailable: lenny-91vu must be open; '
        'exit=${result.exitCode} rows=${rows.length}',
      );
    }
  }

  Future<CommandEvidence> runAdb(List<String> arguments) async {
    final List<String> argv = <String>['-s', serial, ...arguments];
    final ProcessResult result = await runProcess(adb, argv);
    return (
      argv: <String>[adb, ...argv],
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  Future<List<CommandEvidence>> resetAndTrigger() async {
    final List<CommandEvidence> evidence = <CommandEvidence>[
      // The probe app records that it asked in app data. Clearing it is what
      // makes every allow/deny exercise a genuinely fresh runtime prompt.
      await runAdb(<String>['shell', 'pm', 'clear', packageName]),
      await runAdb(<String>['shell', 'pm', 'revoke', packageName, permission]),
      await runAdb(<String>[
        'shell',
        'pm',
        'clear-permission-flags',
        packageName,
        permission,
        'user-set',
        'user-fixed',
      ]),
      for (final List<String> command in trigger) await runAdb(command),
    ];
    if (evidence.any((CommandEvidence value) => value.exitCode != 0)) {
      throw StateError('permission reset or trigger failed: $evidence');
    }
    // com.epi asks from asynchronous startup work, after Monkey returns.
    await Future<void>.delayed(const Duration(seconds: 3));
    return evidence;
  }

  Future<CommandEvidence> _command(String executable, List<String> argv) async {
    final ProcessResult result = await runProcess(executable, argv);
    final CommandEvidence evidence = (
      argv: <String>[executable, ...argv],
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
    if (evidence.exitCode != 0) {
      throw StateError('command failed: $evidence');
    }
    return evidence;
  }

  Future<String> _platformVersion() async {
    final CommandEvidence evidence = await runAdb(<String>[
      'shell',
      'getprop',
      'ro.build.version.release',
    ]);
    final String value = evidence.stdout.trim();
    if (evidence.exitCode != 0 || value.isEmpty) {
      throw StateError('Android version unavailable: $evidence');
    }
    return value;
  }

  bool permissionDialogPresent(NativeSnapshot snapshot) {
    final ObstructionResourceIdPolicy policy =
        ObstructionResourceIdPolicy.defaults();
    return snapshot.nodes.any((NativeNode node) {
      final String? id = node.resourceId;
      if (id == null) return false;
      final int separator = id.indexOf(':id/');
      return separator > 0 &&
          policy.permissionPackage(id.substring(0, separator)) &&
          policy.permissionDialogEntries.contains(id.substring(separator + 4));
    });
  }

  Future<NativeSnapshot> waitForPermissionDialog(
    UiAutomator2Backend backend,
  ) async {
    for (int attempt = 0; attempt < 10; attempt += 1) {
      final NativeSnapshot snapshot = await backend.snapshot();
      if (permissionDialogPresent(snapshot)) return snapshot;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('grant dialog absent after startup wait');
  }

  Future<bool> permissionIsGranted() async {
    final CommandEvidence evidence = await runAdb(<String>[
      'shell',
      'dumpsys',
      'package',
      packageName,
    ]);
    if (evidence.exitCode != 0) {
      throw StateError('grant probe failed: $evidence');
    }
    final RegExpMatch? match = RegExp(
      '${RegExp.escape(permission)}: granted=(true|false)',
    ).firstMatch(evidence.stdout);
    if (match == null) throw StateError('permission absent from dumpsys');
    return match.group(1) == 'true';
  }

  Future<ActionEvidence> exercise(String key, String version) async {
    await resetAndTrigger();
    final RecordingClient client = RecordingClient(clientFactory());
    final UiAutomator2Backend backend = UiAutomator2Backend(
      udid: serial,
      app: packageName,
      platformVersion: version,
      server: appium,
      client: client,
    );
    String result = 'returned';
    bool dialogBefore = false;
    bool dialogAfter = false;
    try {
      await backend.connect(
        extraCapabilities: const <String, Object?>{
          'appium:autoGrantPermissions': false,
        },
      );
      dialogBefore = permissionDialogPresent(
        await waitForPermissionDialog(backend),
      );
      try {
        await backend.press(key);
      } on NativeException catch (error) {
        result = 'refused: ${error.message}';
        if (key != 'dismiss_overlay' ||
            !error.message.contains('permission_allow') ||
            !error.message.contains('permission_deny')) {
          rethrow;
        }
      }
      dialogAfter = permissionDialogPresent(await backend.snapshot());
    } finally {
      await backend.close();
    }
    return (
      key: key,
      result: result,
      dialogBefore: dialogBefore,
      dialogAfter: dialogAfter,
      grantedAfter: await permissionIsGranted(),
      backPosted: client.hits.any((String hit) => hit.endsWith('/back')),
    );
  }

  Future<ActionEvidence> exerciseConnected(
    String key,
    UiAutomator2Backend backend,
    RecordingClient client,
  ) async {
    await resetAndTrigger();
    final bool dialogBefore = permissionDialogPresent(
      await waitForPermissionDialog(backend),
    );
    final int firstRecord = client.records.length;
    String result = 'returned';
    try {
      await backend.press(key);
    } on NativeException catch (error) {
      result = 'refused: ${error.message}';
      if (key != 'dismiss_overlay' ||
          !error.message.contains('permission_allow') ||
          !error.message.contains('permission_deny')) {
        rethrow;
      }
    }
    if (result == 'returned') {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    final bool dialogAfter = permissionDialogPresent(await backend.snapshot());
    return (
      key: key,
      result: result,
      dialogBefore: dialogBefore,
      dialogAfter: dialogAfter,
      grantedAfter: await permissionIsGranted(),
      backPosted: client.records
          .skip(firstRecord)
          .any((RequestEvidence value) => value.path.endsWith('/back')),
    );
  }

  void validateActions(List<ActionEvidence> actions) {
    if (actions.map((ActionEvidence value) => value.key).join(',') !=
        'dismiss_overlay,permission_allow,permission_deny') {
      throw StateError('wrong live action sequence: $actions');
    }
    final ActionEvidence dismiss = actions[0];
    final ActionEvidence allow = actions[1];
    final ActionEvidence deny = actions[2];
    if (actions.any((ActionEvidence value) => !value.dialogBefore) ||
        !dismiss.result.startsWith('refused:') ||
        !dismiss.dialogAfter ||
        dismiss.grantedAfter ||
        dismiss.backPosted ||
        allow.dialogAfter ||
        !allow.grantedAfter ||
        allow.backPosted ||
        deny.dialogAfter ||
        deny.grantedAfter ||
        deny.backPosted) {
      throw StateError('live permission action proof failed: $actions');
    }
  }

  void validateReceipt(Map<String, Object?> value, String fixtureHash) {
    if (value['schemaVersion'] != 1 ||
        value['rawSourceSha256'] != fixtureHash) {
      throw StateError('receipt schema or fixture hash mismatch');
    }
    for (final String key in <String>[
      'serial',
      'androidVersion',
      'manufacturer',
      'model',
      'appiumVersion',
      'uiautomator2Version',
      'capturedAtUtc',
    ]) {
      if (value[key]?.toString().isEmpty ?? true) {
        throw StateError('receipt field is empty: $key');
      }
    }
    if (value['serial'] != serial ||
        value['package'] != packageName ||
        value['permission'] != permission) {
      throw StateError('receipt fixed inputs mismatch');
    }
    for (final String key in <String>[
      'appiumEvidence',
      'uiautomator2Evidence',
    ]) {
      final Object? evidence = value[key];
      if (evidence is! Map || evidence['exitCode'] != 0) {
        throw StateError('non-zero or missing command evidence: $key');
      }
    }
    final Object? requests = value['appiumRequests'];
    if (requests is! List ||
        !requests.whereType<Map<Object?, Object?>>().any(
          (Map<Object?, Object?> record) =>
              record['method'] == 'GET' &&
              record['path'].toString().endsWith('/source') &&
              record['status'] == 200 &&
              record['value'] is String,
        )) {
      throw StateError('receipt has no successful raw /source request');
    }
    final Object? rawActions = value['actions'];
    if (rawActions is! List) throw StateError('receipt actions are missing');
    validateActions(<ActionEvidence>[
      for (final Object? raw in rawActions)
        if (raw is Map)
          (
            key: raw['key'].toString(),
            result: raw['result'].toString(),
            dialogBefore: raw['dialogBefore'] == true,
            dialogAfter: raw['dialogAfter'] == true,
            grantedAfter: raw['grantedAfter'] == true,
            backPosted: raw['backPosted'] == true,
          ),
    ]);
  }

  Map<String, Object?> _commandJson(CommandEvidence value) => <String, Object?>{
    'argv': value.argv,
    'exitCode': value.exitCode,
    'stdout': value.stdout,
    'stderr': value.stderr,
  };

  Map<String, Object?> _actionJson(ActionEvidence value) => <String, Object?>{
    'key': value.key,
    'result': value.result,
    'dialogBefore': value.dialogBefore,
    'dialogAfter': value.dialogAfter,
    'grantedAfter': value.grantedAfter,
    'backPosted': value.backPosted,
  };

  Future<String> _sha256(String source) async {
    final Process process = await Process.start('/usr/bin/shasum', <String>[
      '-a',
      '256',
    ]);
    process.stdin.add(utf8.encode(source));
    await process.stdin.close();
    final String output = await utf8.decoder.bind(process.stdout).join();
    final String error = await utf8.decoder.bind(process.stderr).join();
    final int code = await process.exitCode;
    final String digest = output.trim().split(RegExp(r'\s+')).first;
    if (code != 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw StateError(
        'sha256 failed: exit=$code stdout=$output stderr=$error',
      );
    }
    return digest;
  }

  Future<Map<String, Object?>> _capture({bool writeArtifacts = true}) async {
    final String version = await _platformVersion();
    final CommandEvidence appiumEvidence = await _command(
      '/opt/homebrew/bin/appium',
      <String>['--version'],
    );
    final String appiumVersion = appiumEvidence.stdout.trim();
    if (appiumVersion.isEmpty) throw StateError('empty Appium version');
    final CommandEvidence driverEvidence = await _command(
      '/opt/homebrew/bin/appium',
      <String>['driver', 'list', '--installed', '--json'],
    );
    final Object? driverJson = jsonDecode(driverEvidence.stdout);
    if (driverJson is! Map || driverJson['uiautomator2'] is! Map) {
      throw StateError('malformed UiAutomator2 evidence: $driverEvidence');
    }
    final String driverVersion =
        (driverJson['uiautomator2'] as Map)['version']?.toString() ?? '';
    if (driverVersion.isEmpty) throw StateError('empty UiAutomator2 version');

    final List<CommandEvidence> resetEvidence = await resetAndTrigger();
    final RecordingClient client = RecordingClient(clientFactory());
    final UiAutomator2Backend backend = UiAutomator2Backend(
      udid: serial,
      app: packageName,
      platformVersion: version,
      server: appium,
      client: client,
    );
    late AndroidSessionProvenance provenance;
    late String source;
    late List<ActionEvidence> actions;
    try {
      await backend.connect(
        extraCapabilities: const <String, Object?>{
          'appium:autoGrantPermissions': false,
        },
      );
      provenance =
          backend.sessionProvenance ??
          (throw StateError('Appium session returned no Android provenance'));
      if (provenance.deviceSerial != serial ||
          provenance.androidVersion != version ||
          (provenance.manufacturer?.isEmpty ?? true) ||
          (provenance.model?.isEmpty ?? true)) {
        throw StateError('unexpected Android session provenance: $provenance');
      }
      await waitForPermissionDialog(backend);
      final List<RequestEvidence> sources = client.records
          .where((RequestEvidence value) => value.path.endsWith('/source'))
          .toList();
      if (sources.isEmpty || sources.last.value is! String) {
        throw StateError('expected a raw /source response');
      }
      source = sources.last.value! as String;
      if (!permissionDialogPresent(await _snapshotFromSource(source))) {
        throw StateError('captured /source has no permission dialog');
      }
      actions = <ActionEvidence>[
        for (final String key in <String>[
          'dismiss_overlay',
          'permission_allow',
          'permission_deny',
        ])
          await exerciseConnected(key, backend, client),
      ];
    } finally {
      await backend.close();
    }
    final String raw = source.replaceFirst(
      RegExp(r'^\s*<\?xml[^?]*\?>\s*'),
      '',
    );
    final String digest = await _sha256(raw);
    validateActions(actions);
    final String capturedAt = DateTime.now().toUtc().toIso8601String();
    final Map<String, Object?> json = <String, Object?>{
      'schemaVersion': 1,
      'capturedAtUtc': capturedAt,
      'rawSourceSha256': digest,
      'serial': provenance.deviceSerial,
      'androidVersion': provenance.androidVersion,
      'manufacturer': provenance.manufacturer,
      'model': provenance.model,
      'package': packageName,
      'permission': permission,
      'trigger': trigger,
      'appiumVersion': appiumVersion,
      'uiautomator2Version': driverVersion,
      'appiumEvidence': _commandJson(appiumEvidence),
      'uiautomator2Evidence': _commandJson(driverEvidence),
      'resetAndTriggerEvidence': resetEvidence.map(_commandJson).toList(),
      'appiumRequests': client.records.map((value) => value.toJson()).toList(),
      'actions': actions.map(_actionJson).toList(),
    };
    final String comment =
        '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  Real Appium UiAutomator2 /source capture.
  device serial: ${provenance.deviceSerial}
  Android version: ${provenance.androidVersion}
  manufacturer: ${provenance.manufacturer}
  model: ${provenance.model}
  Appium version: $appiumVersion
  UiAutomator2 version: $driverVersion
  capture timestamp UTC: $capturedAt
  probe package: $packageName
  permission: $permission
  trigger: adb -s $serial shell am force-stop $packageName && adb -s $serial shell monkey -p $packageName 1
  receipt: android_permission_dialog_proof.json
  dismiss_overlay observation: refused; dialog remained visible; no Back sent
  permission_allow observation: dialog closed; requested permission was granted
  permission_deny observation: dialog closed; requested permission was denied
  Visible strings are capture evidence, never detection keys.
-->
''';
    if (writeArtifacts) {
      await fixture.writeAsString('$comment$raw');
      await receipt.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
      );
    }
    return json;
  }

  Future<NativeSnapshot> _snapshotFromSource(String source) async {
    final http.Client fake = MockClient((http.Request request) async {
      if (request.url.path == '/session') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': <String, Object?>{
              'sessionId': 'parse',
              'capabilities': <String, Object?>{},
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/source')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, Object?>{'value': source})),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
    });
    final UiAutomator2Backend backend = UiAutomator2Backend(
      udid: serial,
      app: packageName,
      platformVersion: 'parse',
      client: fake,
    );
    await backend.connect();
    try {
      return await backend.snapshot();
    } finally {
      await backend.close();
    }
  }

  Future<void> capture() async {
    await requireDeviceAvailable();
    final Map<String, Object?> value = await _capture();
    _printPass(value['rawSourceSha256']! as String);
  }

  Future<void> verify() async {
    await requireDeviceAvailable();
    final Map<String, Object?> recorded =
        jsonDecode(await receipt.readAsString()) as Map<String, Object?>;
    final String fixtureSource = await fixture.readAsString();
    final String raw = fixtureSource
        .substring(fixtureSource.indexOf('-->') + 3)
        .trimLeft();
    final String fixtureHash = await _sha256(raw);
    validateReceipt(recorded, fixtureHash);
    final Map<String, Object?> fresh = await _capture(writeArtifacts: false);
    for (final String key in <String>[
      'serial',
      'androidVersion',
      'manufacturer',
      'model',
      'package',
      'permission',
      'appiumVersion',
      'uiautomator2Version',
    ]) {
      if (recorded[key] != fresh[key]) {
        throw StateError('$key differs from receipt');
      }
    }
    _printPass(fixtureHash);
  }

  void _printPass(String digest) {
    stdout.writeln(
      'HARDWARE_PROOF PASS serial=$serial fixture_sha256=$digest '
      'dismiss=refused allow=granted deny=denied',
    );
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      (arguments.single != 'capture' && arguments.single != 'verify')) {
    stderr.writeln(
      'usage: dart run tool/android_permission_dialog_proof.dart capture|verify',
    );
    exitCode = 64;
    return;
  }
  try {
    final AndroidPermissionDialogProof proof = AndroidPermissionDialogProof();
    if (arguments.single == 'capture') {
      await proof.capture();
    } else {
      await proof.verify();
    }
  } on Object catch (error, stack) {
    stderr.writeln('HARDWARE_PROOF FAIL: $error');
    stderr.writeln(stack);
    exitCode = 1;
  }
}
