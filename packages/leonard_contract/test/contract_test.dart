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
  test('buildExtensionMethodName composes ext.exploration.<ns>.<suffix>', () {
    expect(
      ExtensionContext.buildExtensionMethodName('core', 'tap'),
      'ext.exploration.core.tap',
    );
  });

  test('decodeServiceExtensionParams JSON-decodes values, falls back to raw', () {
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
  });

  test('dispatchToolToEnvelope wraps an ok result', () async {
    final body = await dispatchToolToEnvelope(const _EchoTool(), {'a': 1});
    expect(body, contains('"ok":true'));
    expect(body, contains('"a":1'));
  });

  test('dispatchToolToEnvelope catches a throw as dispatch_failed', () async {
    final body = await dispatchToolToEnvelope(const _BoomTool(), const {});
    expect(body, contains('"ok":false'));
    expect(body, contains('dispatch_failed'));
    expect(body, contains('"trace"'));
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
