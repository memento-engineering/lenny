import 'dart:convert';
import 'dart:developer' as developer;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTool extends LeonardTool {
  const _FakeTool(this.name);
  @override
  final String name;
  @override
  String get description => 'fake';
  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _FakeExtension extends LeonardExtension {
  @override
  String get namespace => 'router';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[_FakeTool('go')];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  // A Flutter binding can only be installed once per process; share a single
  // LeonardBinding across this file's tests (see binding_lifecycle_test).
  late LeonardBinding binding;

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[_FakeExtension()],
    )!;
  });

  test('handshake extension is registered exactly once', () {
    expect(kLeonardExtensionPrefix, 'ext.leonard');
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
        'ext.leonard.core.handshake',
        (m, p) async => developer.ServiceExtensionResponse.result('{}'),
      ),
      throwsArgumentError,
    );
  });

  test('core.handshake payload carries the extensions manifest', () async {
    final String raw = await binding.invokeServiceExtension(
      'ext.leonard.core.handshake',
      const <String, String>{},
    );
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json['protocolVersion'], '2');
    expect(json['bindingType'], 'LeonardBinding');
    expect(json['flutterMode'], 'debug');
    expect(json['extensionCount'], 1);
    final List<dynamic> extensions = json['extensions'] as List<dynamic>;
    final Map<String, Map<String, dynamic>> entriesByNs =
        <String, Map<String, dynamic>>{
          for (final dynamic entry in extensions)
            (entry as Map)['namespace'] as String: entry
                .cast<String, dynamic>(),
        };
    final Map<String, List<String>> byNs = <String, List<String>>{
      for (final MapEntry<String, Map<String, dynamic>> entry
          in entriesByNs.entries)
        entry.key: (entry.value['tools'] as List).cast<String>(),
    };
    expect(byNs.keys, containsAll(<String>['core', 'router']));
    expect(byNs['router'], <String>['go']);
    expect(byNs['core'], contains('tap'));
    expect(byNs['core'], contains('tap_at'));
    expect(byNs['core'], contains('done'));
    // bare tokens — no namespacing
    expect(byNs['router']!.every((String t) => !t.contains('.')), isTrue);

    final List<LeonardTool> expectedCoreTools = CoreExtension(
      semantics: SemanticsCapture(),
    ).tools;
    final List<Map<String, Object?>> expectedCoreDescriptors =
        <Map<String, Object?>>[
          for (final LeonardTool tool in expectedCoreTools)
            <String, Object?>{
              'name': tool.name,
              'description': tool.description,
              'inputSchema': tool.inputSchema.raw,
            },
        ];
    expect(entriesByNs['core']!['toolDescriptors'], expectedCoreDescriptors);

    final List<dynamic> actualCoreDescriptors =
        entriesByNs['core']!['toolDescriptors'] as List<dynamic>;
    final Map<String, dynamic> tap =
        (actualCoreDescriptors.firstWhere(
                  (dynamic descriptor) => (descriptor as Map)['name'] == 'tap',
                )
                as Map)
            .cast<String, dynamic>();
    final Map<String, dynamic> tapAt =
        (actualCoreDescriptors.firstWhere(
                  (dynamic descriptor) =>
                      (descriptor as Map)['name'] == 'tap_at',
                )
                as Map)
            .cast<String, dynamic>();
    expect(tap['inputSchema'], <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
      },
      'required': <String>['node_id'],
      'additionalProperties': false,
    });
    expect(tapAt['inputSchema'], <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
        'x': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
        'y': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
      },
      'required': <String>['node_id', 'x', 'y'],
      'additionalProperties': false,
    });
  });

  test(
    'core.handshake advertises screenshot as a capability (debug)',
    () async {
      final String raw = await binding.invokeServiceExtension(
        'ext.leonard.core.handshake',
        const <String, String>{},
      );
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      // screenshot is reachable but is NOT a namespaced tool, so it must be
      // surfaced under `capabilities` (a driver listing tools would otherwise
      // conclude "no screenshot"). flutter_test runs in debug → present.
      expect(json['capabilities'], contains('screenshot'));
      final List<dynamic> extensions = json['extensions'] as List<dynamic>;
      final bool screenshotIsATool = extensions.any(
        (dynamic p) =>
            ((p as Map)['tools'] as List).cast<String>().contains('screenshot'),
      );
      expect(screenshotIsATool, isFalse);
    },
  );
}
