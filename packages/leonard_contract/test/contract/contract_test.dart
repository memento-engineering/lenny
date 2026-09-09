import 'dart:convert';

import 'package:leonard_contract/leonard_contract.dart';
import 'package:test/test.dart';

class _EchoTool extends LeonardTool {
  const _EchoTool();
  @override
  String get name => 'echo';
  @override
  String get description => 'echoes args';
  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args);
}

class _BoomTool extends LeonardTool {
  const _BoomTool();
  @override
  String get name => 'boom';
  @override
  String get description => 'throws';
  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      throw StateError('kaboom');
}

class _DottedTool extends LeonardTool {
  const _DottedTool();
  @override
  String get name => 'bad.name';
  @override
  String get description => '';
  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _StrictTapTool extends LeonardTool {
  const _StrictTapTool();

  @override
  String get name => 'tap';

  @override
  String get description => 'Tap a semantics node.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer'},
    },
    'required': <String>['node_id'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _Ext extends LeonardExtension {
  _Ext(this.namespace, this._tools);
  @override
  final String namespace;
  final List<LeonardTool> _tools;
  @override
  List<LeonardTool> get tools => _tools;
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
  test('exports the Leonard VM-service protocol constants', () {
    expect(kLeonardExtensionPrefix, 'ext.leonard');
    expect(kLeonardProtocolVersion, '2');
  });

  test('buildExtensionMethodName composes ext.leonard.<ns>.<suffix>', () {
    expect(
      ExtensionContext.buildExtensionMethodName('core', 'tap'),
      'ext.leonard.core.tap',
    );
  });

  test(
    'decodeServiceExtensionParams JSON-decodes values, falls back to raw',
    () {
      final out = decodeServiceExtensionParams(<String, String>{
        'n': '5',
        'b': 'true',
        's': 'hello',
        'j': '{"k":1}',
      });
      expect(out['n'], 5);
      expect(out['b'], true);
      expect(out['s'], 'hello');
      expect(out['j'], <String, Object?>{'k': 1});
    },
  );

  test(
    'dispatchToolToEnvelope adds carryForward only for an explicit opt-in',
    () async {
      final defaultEnvelope =
          jsonDecode(
                await dispatchToolToEnvelope(
                  const _EchoTool(),
                  <String, Object?>{'a': 1},
                ),
              )
              as Map<String, dynamic>;
      expect(defaultEnvelope, <String, Object?>{
        'ok': true,
        'value': <String, Object?>{'a': 1},
        'error': null,
      });

      final optedInEnvelope =
          jsonDecode(
                await dispatchToolToEnvelope(
                  const _EchoTool(),
                  <String, Object?>{'a': 1},
                  carryForward: true,
                ),
              )
              as Map<String, dynamic>;
      expect(optedInEnvelope, <String, Object?>{
        'ok': true,
        'value': <String, Object?>{'a': 1},
        'error': null,
        'carryForward': true,
      });
    },
  );

  test('dispatchToolToEnvelope wraps an ok result', () async {
    final body = await dispatchToolToEnvelope(const _EchoTool(), {'a': 1});
    expect(body, contains('"ok":true'));
    expect(body, contains('"a":1'));
  });

  test('dispatchToolToEnvelope catches a throw as dispatch_failed', () async {
    final body = await dispatchToolToEnvelope(
      const _BoomTool(),
      const {},
      carryForward: true,
    );
    final envelope = jsonDecode(body) as Map<String, dynamic>;
    final Object? trace = envelope['trace'];
    expect(trace, isA<String>());
    expect((trace! as String), isNotEmpty);
    expect(envelope, <String, Object?>{
      'ok': false,
      'value': null,
      'error': 'dispatch_failed: Bad state: kaboom',
      'trace': trace,
    });
  });

  group('ExtensionRegistry', () {
    test('register + mergedTools prefixes namespace; manifest lists tools', () {
      final r = ExtensionRegistry();
      r.register(_Ext('core', const [_EchoTool()]));
      final merged = r.mergedTools();
      expect(merged.keys, contains('core.echo'));
      expect(r.manifest.single.namespace, 'core');
      expect(r.manifest.single.tools, <String>['echo']);
    });

    test('handshakeManifest preserves ordered device tool descriptors', () {
      final r = ExtensionRegistry();
      r.register(_Ext('core', const <LeonardTool>[_StrictTapTool()]));

      final entry = r.handshakeManifest.single;

      expect(entry.namespace, 'core');
      expect(entry.tools, <String>['tap']);
      expect(entry.toolDescriptors, <Map<String, Object?>>[
        <String, Object?>{
          'name': 'tap',
          'description': 'Tap a semantics node.',
          'inputSchema': const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'node_id': <String, Object?>{'type': 'integer'},
            },
            'required': <String>['node_id'],
            'additionalProperties': false,
          },
        },
      ]);
      expect(r.manifest.single.tools, <String>['tap']);
    });

    test('rejects duplicate namespace', () {
      final r = ExtensionRegistry();
      r.register(_Ext('core', const [_EchoTool()]));
      expect(() => r.register(_Ext('core', const [])), throwsStateError);
    });

    test('rejects invalid namespace', () {
      final r = ExtensionRegistry();
      expect(() => r.register(_Ext('Bad-NS', const [])), throwsArgumentError);
    });

    test('rejects a dotted tool name', () {
      final r = ExtensionRegistry();
      r.register(_Ext('core', const [_DottedTool()]));
      expect(r.mergedTools, throwsArgumentError);
    });
  });
}
