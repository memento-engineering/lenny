// Tests for ExtensionRegistry's documented invariants.
//
// The class dartdoc on ExtensionRegistry enumerates four enforced
// behaviours: namespace shape and uniqueness, mandatory prefixing with bare
// tool names, registration-order preservation, and per-method exception
// isolation with 3-strikes auto-disable (PRD §17). Each claim gets a test
// here, and each assertion is written to fail on a specific single-line
// change to the source.

import 'package:leonard_contract/leonard_contract.dart';
import 'package:test/test.dart';

class _Tool extends LeonardTool {
  const _Tool(this.name);
  @override
  final String name;
  @override
  String get description => 'tool $name';
  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args);
}

/// An extension whose lifecycle methods throw on demand, so the registry's
/// exception-isolation guard can be driven deterministically.
class _ProgrammableExt extends LeonardExtension {
  _ProgrammableExt(
    this.namespace, {
    this.tools = const <LeonardTool>[],
    this.throwOnInitialize = false,
    this.throwOnDispose = false,
    this.busy = const BusyState(isBusy: true, reason: 'working'),
  });

  @override
  final String namespace;
  @override
  final List<LeonardTool> tools;

  final bool throwOnInitialize;
  final bool throwOnDispose;
  final BusyState busy;

  /// Flip to make the next [busyState]/[onActionExecuted] call throw.
  bool throwOnDispatch = false;

  int busyStateCalls = 0;
  int onActionExecutedCalls = 0;
  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    initializeCalls++;
    if (throwOnInitialize) throw StateError('initialize failed: $namespace');
  }

  @override
  Future<BusyState> busyState() async {
    busyStateCalls++;
    if (throwOnDispatch) throw StateError('busyState failed: $namespace');
    return busy;
  }

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {
    onActionExecutedCalls++;
    if (throwOnDispatch) throw StateError('onActionExecuted failed');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (throwOnDispose) throw StateError('dispose failed: $namespace');
  }
}

ExecutedAction _action() => const ExecutedAction(
  toolName: 'core.echo',
  args: <String, Object?>{},
  result: ToolResult(ok: true),
);

void main() {
  group('namespace validation', () {
    // The reject case was already covered. These cover the ACCEPT side: a
    // narrowed character class silently rejects legitimate namespaces, and
    // no reject-only test can see that.
    test('accepts the full documented character class', () {
      for (final ns in <String>['core', 'a', 'core2', 'a_b', 'x9_z0']) {
        final r = ExtensionRegistry();
        expect(
          () => r.register(_ProgrammableExt(ns)),
          returnsNormally,
          reason: '$ns matches ^[a-z][a-z0-9_]\$ and must be accepted',
        );
      }
    });

    test('rejects namespaces that violate the documented shape', () {
      for (final ns in <String>[
        '',
        'Core',
        '9core',
        '_core',
        'core-x',
        'a.b',
      ]) {
        final r = ExtensionRegistry();
        expect(
          () => r.register(_ProgrammableExt(ns)),
          throwsArgumentError,
          reason: '$ns does not match ^[a-z][a-z0-9_]*\$',
        );
      }
    });

    // throwsArgumentError proves only that something threw. These assert
    // WHAT was reported, which is what a caller actually reads.
    test('the namespace ArgumentError names the offending value and param', () {
      final r = ExtensionRegistry();
      expect(
        () => r.register(_ProgrammableExt('Bad-NS')),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 'Bad-NS')
              .having((e) => e.name, 'name', 'namespace')
              .having(
                (e) => e.message,
                'message',
                r'must match ^[a-z][a-z0-9_]*$',
              ),
        ),
      );
    });

    test('the duplicate-namespace StateError names the namespace', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core'));
      expect(
        () => r.register(_ProgrammableExt('core')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'duplicate extension namespace: core',
          ),
        ),
      );
    });
  });

  group('tool merging', () {
    test('the dotted-tool ArgumentError names the value and param', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core', tools: const [_Tool('bad.name')]));
      expect(
        r.mergedTools,
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 'bad.name')
              .having((e) => e.name, 'name', 'tool.name')
              .having(
                (e) => e.message,
                'message',
                'must be bare token (no ".")',
              ),
        ),
      );
    });

    test('an inter-extension collision reports the fully-qualified name', () {
      // Two extensions cannot collide on a bare name (the namespace differs),
      // so the collision path needs a tool whose bare name repeats within one
      // extension.
      final r = ExtensionRegistry();
      r.register(
        _ProgrammableExt('core', tools: const [_Tool('echo'), _Tool('echo')]),
      );
      expect(
        r.mergedTools,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'tool name collision: core.echo',
          ),
        ),
      );
    });

    test('mergedTools returns exactly the prefixed names, nothing more', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core', tools: const [_Tool('echo')]));
      r.register(_ProgrammableExt('net', tools: const [_Tool('echo')]));
      // Set equality, not `contains` — `contains` cannot see an extra or a
      // wrongly-prefixed key.
      expect(r.mergedTools().keys.toSet(), <String>{'core.echo', 'net.echo'});
    });

    test('mergedTools finalizes: register afterwards is a StateError', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core'));
      r.mergedTools();
      expect(
        () => r.register(_ProgrammableExt('net')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExtensionRegistry already finalized',
          ),
        ),
      );
    });

    test('finalize is an alias for mergedTools', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core', tools: const [_Tool('echo')]));
      expect(r.finalize().keys.toSet(), <String>{'core.echo'});
      expect(() => r.register(_ProgrammableExt('net')), throwsStateError);
    });
  });

  group('registration order', () {
    // The dartdoc promises order preservation "across every dispatch". A
    // single-extension test cannot observe order at all.
    test(
      'namespaces, manifest and extensions all report registration order',
      () {
        final r = ExtensionRegistry();
        final first = _ProgrammableExt('zulu', tools: const [_Tool('a')]);
        final second = _ProgrammableExt('alpha', tools: const [_Tool('b')]);
        final third = _ProgrammableExt('mike', tools: const [_Tool('c')]);
        r
          ..register(first)
          ..register(second)
          ..register(third);

        expect(r.namespaces, <String>['zulu', 'alpha', 'mike']);
        expect(r.manifest.map((m) => m.namespace).toList(), <String>[
          'zulu',
          'alpha',
          'mike',
        ]);
        expect(r.manifest.map((m) => m.tools).toList(), <List<String>>[
          ['a'],
          ['b'],
          ['c'],
        ]);
        expect(r.extensions, <LeonardExtension>[first, second, third]);
      },
    );

    test('dispatch preserves registration order', () async {
      final r = ExtensionRegistry();
      r
        ..register(_ProgrammableExt('zulu'))
        ..register(_ProgrammableExt('alpha'));
      final states = await r.busyStateAll();
      expect(states.map((e) => e.key).toList(), <String>['zulu', 'alpha']);
    });

    test('the order-reporting views are unmodifiable', () {
      final r = ExtensionRegistry();
      r.register(_ProgrammableExt('core'));
      expect(() => r.namespaces.add('x'), throwsUnsupportedError);
      expect(() => r.extensions.clear(), throwsUnsupportedError);
      expect(() => r.manifest.clear(), throwsUnsupportedError);
      expect(
        () => r.mergedTools()['core.x'] = const _Tool('x'),
        throwsUnsupportedError,
      );
    });
  });

  group('busyStateAll', () {
    test(
      'returns one entry per extension carrying its reported state',
      () async {
        final r = ExtensionRegistry();
        r
          ..register(
            _ProgrammableExt(
              'core',
              busy: const BusyState(isBusy: true, reason: 'navigating'),
            ),
          )
          ..register(_ProgrammableExt('net', busy: BusyState.idle));

        final states = await r.busyStateAll();
        expect(states, hasLength(2));
        expect(states[0].key, 'core');
        expect(states[0].value.isBusy, isTrue);
        expect(states[0].value.reason, 'navigating');
        expect(states[1].key, 'net');
        expect(states[1].value.isBusy, isFalse);
      },
    );
  });

  group('exception isolation (PRD §17)', () {
    test('initializeAll runs every extension and never rethrows', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final bad = _ProgrammableExt('bad', throwOnInitialize: true);
      final good = _ProgrammableExt('good');
      r
        ..register(bad)
        ..register(good);

      await r.initializeAll();

      expect(bad.initializeCalls, 1);
      // The throw must not stop the loop.
      expect(good.initializeCalls, 1);
      expect(logs, hasLength(1));
      expect(logs.single, contains('extension bad initialize failed'));
      expect(logs.single, contains('initialize failed: bad'));
    });

    test('an init-failed extension is never dispatched again', () async {
      final r = ExtensionRegistry();
      final bad = _ProgrammableExt('bad', throwOnInitialize: true);
      final good = _ProgrammableExt('good');
      r
        ..register(bad)
        ..register(good);
      await r.initializeAll();

      final states = await r.busyStateAll();
      await r.onActionExecutedAll(_action());

      // Short-circuited before the plugin call.
      expect(bad.busyStateCalls, 0);
      expect(bad.onActionExecutedCalls, 0);
      // ...but it still reports, as idle, in its registration slot.
      expect(states.map((e) => e.key).toList(), <String>['bad', 'good']);
      expect(states[0].value.isBusy, isFalse);
      // The healthy extension is unaffected.
      expect(good.busyStateCalls, 1);
      expect(good.onActionExecutedCalls, 1);
    });

    test('a throwing dispatch yields the fallback and logs', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final ext = _ProgrammableExt('core')..throwOnDispatch = true;
      r.register(ext);

      final states = await r.busyStateAll();

      expect(states.single.key, 'core');
      expect(states.single.value.isBusy, isFalse);
      expect(logs.single, contains('extension core busyState threw'));
      expect(logs.single, contains('busyState failed: core'));
    });

    test('the third failure disables and emits one auto-disable line', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final ext = _ProgrammableExt('core')..throwOnDispatch = true;
      r.register(ext);

      await r.busyStateAll();
      await r.busyStateAll();
      expect(
        logs.where((l) => l.contains('auto-disabled')),
        isEmpty,
        reason: 'the guard must not disable before the third failure',
      );

      await r.busyStateAll();
      expect(ext.busyStateCalls, 3);
      expect(
        logs.where((l) => l.contains('auto-disabled')).single,
        '[Leonard] extension core auto-disabled after 3 failures in busyState',
      );

      // Disabled means the plugin is not called again, ever.
      await r.busyStateAll();
      await r.busyStateAll();
      expect(ext.busyStateCalls, 3);
      // ...and the disable line is emitted once, not on every later call.
      expect(logs.where((l) => l.contains('auto-disabled')), hasLength(1));
    });

    test('a success resets the consecutive-failure counter', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final ext = _ProgrammableExt('core')..throwOnDispatch = true;
      r.register(ext);

      await r.busyStateAll();
      await r.busyStateAll();
      ext.throwOnDispatch = false;
      await r.busyStateAll(); // resets to 0
      ext.throwOnDispatch = true;
      await r.busyStateAll();
      await r.busyStateAll();

      expect(
        logs.where((l) => l.contains('auto-disabled')),
        isEmpty,
        reason: '2 + 2 non-consecutive failures must not disable',
      );
      expect(ext.busyStateCalls, 5);
    });

    test('the disable counter is per method, not per extension', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final ext = _ProgrammableExt('core')..throwOnDispatch = true;
      r.register(ext);

      // Three busyState failures disable busyState only.
      await r.busyStateAll();
      await r.busyStateAll();
      await r.busyStateAll();
      expect(ext.busyStateCalls, 3);

      await r.onActionExecutedAll(_action());
      expect(
        ext.onActionExecutedCalls,
        1,
        reason: 'onActionExecuted has its own counter and is still live',
      );
      expect(
        logs.where((l) => l.contains('auto-disabled in busyState')),
        isEmpty,
      );
      expect(
        logs
            .where((l) => l.contains('auto-disabled'))
            .where((l) => l.contains('busyState')),
        hasLength(1),
      );
    });

    test('disposeAll disposes every extension even when one throws', () async {
      final logs = <String>[];
      final r = ExtensionRegistry(logger: logs.add);
      final bad = _ProgrammableExt('bad', throwOnDispose: true);
      final good = _ProgrammableExt('good');
      r
        ..register(bad)
        ..register(good);

      await r.disposeAll();

      expect(bad.disposeCalls, 1);
      expect(good.disposeCalls, 1);
      expect(logs.single, contains('extension bad dispose threw'));
      expect(logs.single, contains('dispose failed: bad'));
    });

    test('dispose is not gated by the dispatch guard', () async {
      // disposeAll has its own try/catch and must run even for an
      // init-failed extension, or resources leak.
      final r = ExtensionRegistry();
      final bad = _ProgrammableExt('bad', throwOnInitialize: true);
      r.register(bad);
      await r.initializeAll();
      await r.disposeAll();
      expect(bad.disposeCalls, 1);
    });

    test('the default logger is a no-op, not a crash', () async {
      final r = ExtensionRegistry();
      final ext = _ProgrammableExt('core', throwOnInitialize: true);
      r.register(ext);
      await expectLater(r.initializeAll(), completes);
    });
  });
}
