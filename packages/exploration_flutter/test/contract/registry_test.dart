import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exploration_flutter/contract.dart';

class _FakeTool extends ExplorationTool {
  const _FakeTool(this.name);
  @override
  final String name;
  @override
  String get description => '';
  @override
  JsonSchema get inputSchema => const JsonSchema({});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _OrderPlugin extends ExplorationPlugin {
  _OrderPlugin(
    this.namespace, {
    required this.log,
    this.toolNames = const <String>[],
  });

  @override
  final String namespace;
  final List<String> log;
  final List<String> toolNames;

  @override
  List<ExplorationTool> get tools =>
      toolNames.map<ExplorationTool>(_FakeTool.new).toList(growable: false);

  @override
  Future<void> initialize(PluginContext ctx) async {
    log.add('init:$namespace');
  }

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    log.add('obs:$namespace');
    return <String, Object?>{'k': 1, 'unknown_future_field': 'opaque'};
  }

  @override
  Future<BusyState> busyState() async {
    log.add('busy:$namespace');
    return BusyState.idle;
  }

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {
    log.add('act:$namespace');
  }

  @override
  Future<void> dispose() async {
    log.add('dispose:$namespace');
  }
}

class _ThrowOnObserve extends _OrderPlugin {
  _ThrowOnObserve(super.namespace, {required super.log});

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    log.add('obs:$namespace');
    throw StateError('boom');
  }
}

class _ThrowOnDispose extends _OrderPlugin {
  _ThrowOnDispose(super.namespace, {required super.log});

  @override
  Future<void> dispose() async {
    log.add('dispose:$namespace');
    throw StateError('boom');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = SchedulerBinding.instance;

  PluginRegistry build() => PluginRegistry(scheduler: scheduler);

  test('rejects bad namespace', () {
    final r = build();
    expect(
      () => r.register(_OrderPlugin('Bad-NS', log: <String>[])),
      throwsArgumentError,
    );
  });

  test('rejects duplicate namespace', () {
    final r = build();
    r.register(_OrderPlugin('a', log: <String>[]));
    expect(
      () => r.register(_OrderPlugin('a', log: <String>[])),
      throwsStateError,
    );
  });

  test('prefixes tool names and rejects dotted names', () {
    final r1 = build();
    r1.register(
      _OrderPlugin('router', log: <String>[], toolNames: const ['navigate_to']),
    );
    final tools = r1.mergedTools();
    expect(tools.keys, contains('router.navigate_to'));

    final r2 = build();
    r2.register(
      _OrderPlugin('x', log: <String>[], toolNames: const ['a.b']),
    );
    expect(r2.mergedTools, throwsArgumentError);
  });

  test('rejects intra-plugin tool collision', () {
    final r = build();
    r.register(
      _OrderPlugin('x', log: <String>[], toolNames: const ['t', 't']),
    );
    expect(r.mergedTools, throwsStateError);
  });

  test('preserves registration order across all dispatches', () async {
    final log = <String>[];
    final r = build();
    r.register(_OrderPlugin('a', log: log));
    r.register(_OrderPlugin('b', log: log));
    await r.initializeAll();
    await r.observeAll(
      const ObservationContext(turn: 0, sinceLastAction: Duration.zero),
    );
    await r.busyStateAll();
    await r.onActionExecutedAll(
      const ExecutedAction(
        toolName: 'core.tap',
        args: <String, Object?>{},
        result: ToolResult(ok: true),
      ),
    );
    await r.disposeAll();
    expect(log, <String>[
      'init:a',
      'init:b',
      'obs:a',
      'obs:b',
      'busy:a',
      'busy:b',
      'act:a',
      'act:b',
      'dispose:a',
      'dispose:b',
    ]);
  });

  test('observe fragment passes unknown fields through', () async {
    final r = build();
    r.register(_OrderPlugin('a', log: <String>[]));
    await r.initializeAll();
    final out = await r.observeAll(
      const ObservationContext(turn: 0, sinceLastAction: Duration.zero),
    );
    expect(
      out['a'],
      <String, Object?>{'k': 1, 'unknown_future_field': 'opaque'},
    );
  });

  test('per-method exception isolation and 3-strikes auto-disable', () async {
    final log = <String>[];
    final r = build();
    r.register(_ThrowOnObserve('x', log: log));
    r.register(_OrderPlugin('y', log: log));
    await r.initializeAll();
    for (var i = 0; i < 5; i++) {
      final out = await r.observeAll(
        ObservationContext(turn: i, sinceLastAction: Duration.zero),
      );
      expect(out.containsKey('x'), isFalse);
      expect(out.containsKey('y'), isTrue);
    }
    expect(log.where((s) => s == 'obs:x').length, 3);
  });

  test('dispose isolation runs every plugin', () async {
    final log = <String>[];
    final r = build();
    r.register(_ThrowOnDispose('a', log: log));
    r.register(_OrderPlugin('b', log: log));
    await r.disposeAll();
    expect(log, <String>['dispose:a', 'dispose:b']);
  });
}
