import 'dart:convert';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_agent/leonard_agent.dart' show Observation;
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';
import 'package:test/test.dart';

void main() {
  group('ExplorationHost wire shapes', () {
    test('handshake advertises protocol version + tool manifest', () async {
      final host = ExplorationHost(
        extensions: <LeonardExtension>[_DemoExtension()],
      );
      final hs = jsonDecode(await host.handshakeJson()) as Map<String, dynamic>;
      expect(hs['protocolVersion'], '2');
      final exts = (hs['extensions'] as List).cast<Map<String, dynamic>>();
      expect(exts, hasLength(1));
      expect(exts.single['namespace'], 'demo');
      expect(exts.single['tools'], <String>['bump']);
    });

    test('observation is a valid Observation bundle carrying the fragment',
        () async {
      final host = ExplorationHost(
        extensions: <LeonardExtension>[_DemoExtension()],
      );
      final env =
          jsonDecode(await host.observationJson()) as Map<String, dynamic>;
      expect(env['type'], 'Observation');
      final value = (env['value'] as Map).cast<String, dynamic>();
      // The real consumer (leonard_agent) accepts the bundle.
      final Observation obs = Observation.fromJson(value);
      expect(obs.extensions.keys, contains('demo'));
      // The projected field survives serialization.
      expect(jsonEncode(value['extensions']), contains('count'));
    });

    test('invoke dispatches to the tool and returns the {ok,value} envelope',
        () async {
      final host = ExplorationHost(
        extensions: <LeonardExtension>[_DemoExtension()],
      );
      // The driver JSON-encodes each arg value on the wire: by:2 -> "2".
      final env = jsonDecode(
        await host.invokeToolJson('demo.bump', <String, String>{'by': '2'}),
      ) as Map<String, dynamic>;
      expect(env['ok'], true);
      expect((env['value'] as Map)['count'], 2);
    });

    test('a tools-only extension contributes no observation fragment',
        () async {
      final host = ExplorationHost(
        extensions: <LeonardExtension>[_ToolsOnlyExtension()],
      );
      final value = (jsonDecode(await host.observationJson())
          as Map)['value'] as Map;
      expect(value['extensions'], isEmpty);
      final hs = jsonDecode(await host.handshakeJson()) as Map<String, dynamic>;
      expect(((hs['extensions'] as List).single as Map)['tools'],
          <String>['noop']);
    });

    test('invoking an unknown tool throws ArgumentError', () async {
      final host = ExplorationHost(
        extensions: <LeonardExtension>[_DemoExtension()],
      );
      expect(
        () => host.invokeToolJson('demo.nope', const <String, String>{}),
        throwsArgumentError,
      );
    });
  });
}

/// A perception+tools extension: `bump` mutates a counter that the
/// observation fragment projects.
class _DemoExtension extends LeonardExtension with PerceptionExtension {
  int _count = 0;

  @override
  String get namespace => 'demo';

  @override
  List<LeonardTool> get tools => <LeonardTool>[_BumpTool(this)];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}

  @override
  Seed buildPerception() => _DemoPerception(_count);
}

class _DemoPerception extends StatelessPerception {
  const _DemoPerception(this.count);

  final int count;

  @override
  Seed build(PerceptionContext ctx) =>
      Node('demo', children: <Seed>[Field('count', count)]);
}

class _BumpTool extends LeonardTool {
  _BumpTool(this.owner);

  final _DemoExtension owner;

  @override
  String get name => 'bump';

  @override
  String get description => 'Increment the demo counter.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'by': <String, Object?>{'type': 'integer'},
        },
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    owner._count += (args['by'] as int?) ?? 1;
    return ToolResult(ok: true, value: <String, Object?>{'count': owner._count});
  }
}

class _ToolsOnlyExtension extends LeonardExtension {
  @override
  String get namespace => 'toolsonly';

  @override
  List<LeonardTool> get tools => <LeonardTool>[_NoopTool()];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class _NoopTool extends LeonardTool {
  @override
  String get name => 'noop';

  @override
  String get description => 'Does nothing.';

  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});

  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true, value: <String, Object?>{});
}
