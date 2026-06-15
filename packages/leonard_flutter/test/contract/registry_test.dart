import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';

class _FakeTool extends LeonardTool {
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

class _OrderExtension extends LeonardExtension {
  _OrderExtension(
    this.namespace, {
    required this.log,
    this.toolNames = const <String>[],
  });

  @override
  final String namespace;
  final List<String> log;
  final List<String> toolNames;

  @override
  List<LeonardTool> get tools =>
      toolNames.map<LeonardTool>(_FakeTool.new).toList(growable: false);

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    log.add('init:$namespace');
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

class _ThrowOnBusy extends _OrderExtension {
  _ThrowOnBusy(super.namespace, {required super.log});

  @override
  Future<BusyState> busyState() async {
    log.add('busy:$namespace');
    throw StateError('boom');
  }
}

class _ThrowOnDispose extends _OrderExtension {
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

  ExtensionRegistry build() => ExtensionRegistry(scheduler: scheduler);

  test('rejects bad namespace', () {
    final r = build();
    expect(
      () => r.register(_OrderExtension('Bad-NS', log: <String>[])),
      throwsArgumentError,
    );
  });

  test('rejects duplicate namespace', () {
    final r = build();
    r.register(_OrderExtension('a', log: <String>[]));
    expect(
      () => r.register(_OrderExtension('a', log: <String>[])),
      throwsStateError,
    );
  });

  test('prefixes tool names and rejects dotted names', () {
    final r1 = build();
    r1.register(
      _OrderExtension(
        'router',
        log: <String>[],
        toolNames: const ['navigate_to'],
      ),
    );
    final tools = r1.mergedTools();
    expect(tools.keys, contains('router.navigate_to'));

    final r2 = build();
    r2.register(
      _OrderExtension('x', log: <String>[], toolNames: const ['a.b']),
    );
    expect(r2.mergedTools, throwsArgumentError);
  });

  test('rejects intra-extension tool collision', () {
    final r = build();
    r.register(
      _OrderExtension('x', log: <String>[], toolNames: const ['t', 't']),
    );
    expect(r.mergedTools, throwsStateError);
  });

  test('preserves registration order across all dispatches', () async {
    final log = <String>[];
    final r = build();
    r.register(_OrderExtension('a', log: log));
    r.register(_OrderExtension('b', log: log));
    await r.initializeAll();
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
      'busy:a',
      'busy:b',
      'act:a',
      'act:b',
      'dispose:a',
      'dispose:b',
    ]);
  });

  test('per-method exception isolation and 3-strikes auto-disable', () async {
    final log = <String>[];
    final r = build();
    r.register(_ThrowOnBusy('x', log: log));
    r.register(_OrderExtension('y', log: log));
    await r.initializeAll();
    for (var i = 0; i < 5; i++) {
      final out = await r.busyStateAll();
      // Both extensions always yield a BusyState entry (the thrower's is the
      // idle fallback from the registry guard), so the map order is stable.
      expect(
        out.map((MapEntry<String, BusyState> e) => e.key).toList(),
        <String>['x', 'y'],
      );
    }
    // The throwing extension is dispatched 3 times, then auto-disabled.
    expect(log.where((s) => s == 'busy:x').length, 3);
    // The healthy extension keeps being dispatched every iteration.
    expect(log.where((s) => s == 'busy:y').length, 5);
  });

  test('dispose isolation runs every extension', () async {
    final log = <String>[];
    final r = build();
    r.register(_ThrowOnDispose('a', log: log));
    r.register(_OrderExtension('b', log: log));
    await r.disposeAll();
    expect(log, <String>['dispose:a', 'dispose:b']);
  });
}
