/// Unit tests for [DefaultLoopHost] — the production [LoopHost] that
/// wires the loop driver to an [ExplorationSession] +
/// [VmServiceClient] + caller-supplied tool descriptors.
///
/// Tests use [ExplorationSession.forTest] over a [VmServiceClient.forTest]
/// wrapping a hand-rolled fake [VmService] that overrides only
/// `callServiceExtension`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

// ===========================================================================
// Fakes
// ===========================================================================

class _FakeVmService extends VmService {
  _FakeVmService(this._handler)
      : super(
          const Stream<dynamic>.empty(),
          (_) {},
        );

  final Future<Response> Function(
    String method,
    Map<String, dynamic>? args,
  ) _handler;

  bool disposed = false;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    return _handler(method, args);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Response _resp(Map<String, dynamic> json) {
  final r = Response();
  r.json = json;
  return r;
}

/// Build a fake VM-service that responds to:
///   * `ext.flutter.exploration.handshake` with the supplied plugin
///     manifest (namespaces only — descriptors are caller-supplied).
///   * `ext.flutter.exploration.core.get_stable_observation` via
///     [observationHandler] (defaults to one node, route `/`).
///   * `ext.flutter.exploration.core.executeAction` via
///     [executeActionHandler] (defaults to `{ok:true}`).
_FakeVmService _fakeVm({
  List<Map<String, dynamic>> plugins = const <Map<String, dynamic>>[],
  Future<Map<String, dynamic>> Function(Map<String, dynamic>?)?
      observationHandler,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>?)?
      executeActionHandler,
}) {
  return _FakeVmService((method, args) async {
    switch (method) {
      case 'ext.flutter.exploration.handshake':
        return _resp(<String, dynamic>{
          'contractVersion': '1.0.0',
          'plugins': plugins,
        });
      case 'ext.flutter.exploration.core.get_stable_observation':
        final obs = observationHandler != null
            ? await observationHandler(args)
            : <String, dynamic>{
                'value': <String, dynamic>{
                  'semantics': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 1,
                      'role': 'button',
                      'label': 'OK',
                      'state': <String>[],
                      'actions': <String>['tap'],
                      'rect': <int>[0, 0, 100, 40],
                    },
                  ],
                  'routes': <String>['/'],
                  'errors': <Map<String, dynamic>>[],
                  'plugins': <String, dynamic>{},
                  'stability': <String, dynamic>{
                    'policy': 'action_relative',
                    'terminated_by': 'all_idle',
                    'duration_ms': 0,
                    'framework_busy': <String, dynamic>{},
                    'plugins_busy': <Map<String, dynamic>>[],
                  },
                },
              };
        return _resp(obs);
      case 'ext.flutter.exploration.core.executeAction':
        final result = executeActionHandler != null
            ? await executeActionHandler(args)
            : <String, dynamic>{'ok': true};
        return _resp(result);
      default:
        throw RPCError('callServiceExtension', -32601, 'method not found');
    }
  });
}

Future<ExplorationSession> _newStartedSession(_FakeVmService vm) async {
  final session = ExplorationSession.forTest(
    VmServiceClient.forTest(vm, 'iso-1'),
  );
  await session.start('test goal', const ExplorationConfig());
  return session;
}

ToolDescriptor _tool(String name) => ToolDescriptor(
      name: name,
      description: 'desc for $name',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    );

// ===========================================================================
// Trajectory sink for the integration test (step 7.7).
// ===========================================================================

class _MemorySink extends TrajectorySink {
  final List<String> lines = <String>[];
  bool closed = false;

  @override
  Future<void> writeLine(String line) async => lines.add(line);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async => closed = true;
}

class _FakeProvider extends ModelProvider {
  _FakeProvider(this._decision);
  final ModelDecision _decision;

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
        vision: false,
        preserveThinking: false,
        maxContext: 8000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();

  @override
  Future<ModelDecision> decide(
    PromptPayload prompt,
    ActionSchema schema,
  ) async =>
      _decision;
}

void main() {
  group('DefaultLoopHost.fromSession — getters echo', () {
    test('agentsMd and goal echo constructor arguments', () async {
      final vm = _fakeVm();
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'login flow',
        agentsMd: '# AGENTS\nrun the app',
      );

      expect(host.goal, 'login flow');
      expect(host.agentsMd, '# AGENTS\nrun the app');
      await session.end();
    });
  });

  group('DefaultLoopHost.mergedTools / activePluginNamespaces', () {
    test('mergedTools returns core ∪ active plugin descriptors', () async {
      final vm = _fakeVm(plugins: <Map<String, dynamic>>[
        <String, dynamic>{
          'namespace': 'router',
          'tools': <String>['router.go'],
        },
        <String, dynamic>{
          'namespace': 'forms',
          'tools': <String>['forms.fill'],
        },
      ]);
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap'), _tool('core.wait')],
        pluginTools: <String, List<ToolDescriptor>>{
          'router': <ToolDescriptor>[_tool('router.go')],
          'forms': <ToolDescriptor>[_tool('forms.fill')],
        },
        goal: 'g',
        agentsMd: 'a',
      );

      final names = host.mergedTools().map((t) => t.name).toList();
      expect(
        names,
        equals(<String>['core.tap', 'core.wait', 'router.go', 'forms.fill']),
      );
      expect(host.activePluginNamespaces(), equals(<String>{'router', 'forms'}));
      await session.end();
    });

    test('activePluginNamespaces filters out namespaces missing from '
        'pluginTools map', () async {
      // Handshake reports `router` and `unknown` plugins; only `router`
      // has descriptors. The unknown namespace is silently ignored.
      final vm = _fakeVm(plugins: <Map<String, dynamic>>[
        <String, dynamic>{'namespace': 'router', 'tools': <String>['router.go']},
        <String, dynamic>{'namespace': 'unknown', 'tools': <String>['unknown.x']},
      ]);
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: <String, List<ToolDescriptor>>{
          'router': <ToolDescriptor>[_tool('router.go')],
        },
        goal: 'g',
        agentsMd: 'a',
      );

      expect(host.activePluginNamespaces(), equals(<String>{'router'}));
      expect(
        host.mergedTools().map((t) => t.name).toList(),
        equals(<String>['core.wait', 'router.go']),
      );
      await session.end();
    });

    test('mergedTools excludes auto-disabled namespaces', () async {
      final vm = _fakeVm(plugins: <Map<String, dynamic>>[
        <String, dynamic>{'namespace': 'router', 'tools': <String>['router.go']},
        <String, dynamic>{'namespace': 'forms', 'tools': <String>['forms.fill']},
      ]);
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: <String, List<ToolDescriptor>>{
          'router': <ToolDescriptor>[_tool('router.go')],
          'forms': <ToolDescriptor>[_tool('forms.fill')],
        },
        goal: 'g',
        agentsMd: 'a',
      );

      host.disablePlugin('router', 'flaky');
      expect(
        host.mergedTools().map((t) => t.name).toList(),
        equals(<String>['core.wait', 'forms.fill']),
      );
      expect(host.activePluginNamespaces(), equals(<String>{'forms'}));
      await session.end();
    });
  });

  group('DefaultLoopHost.disablePlugin idempotent', () {
    test('repeated disable on the same namespace emits PluginAutoDisabled '
        'exactly once', () async {
      final vm = _fakeVm(plugins: <Map<String, dynamic>>[
        <String, dynamic>{'namespace': 'router', 'tools': <String>['router.go']},
      ]);
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: <String, List<ToolDescriptor>>{
          'router': <ToolDescriptor>[_tool('router.go')],
        },
        goal: 'g',
        agentsMd: 'a',
      );

      // Buffer events so the first disable event isn't dropped before the
      // listener attaches.
      final List<PluginAutoDisabled> events = <PluginAutoDisabled>[];
      final sub = session.progress.listen((e) {
        if (e is PluginAutoDisabled) events.add(e);
      });

      host.disablePlugin('router', 'flaky #1');
      host.disablePlugin('router', 'flaky #2');
      host.disablePlugin('router', 'flaky #3');

      // Drain the broadcast stream.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, hasLength(1));
      expect(events.single.namespace, 'router');
      expect(events.single.reason, 'flaky #1');

      // State stays disabled regardless of repeats.
      expect(host.activePluginNamespaces(), isEmpty);
      expect(
        host.mergedTools().map((t) => t.name).toList(),
        equals(<String>['core.wait']),
      );

      await session.end();
    });
  });

  group('DefaultLoopHost.observe', () {
    test('observe returns a typed Observation (one node, one route)',
        () async {
      final vm = _fakeVm();
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      final Observation obs = await host.observe();
      expect(obs.core.routeStack, equals(<String>['/']));
      expect(obs.core.nodes, hasLength(1));
      expect(obs.core.nodes[1]?.role, 'button');
      expect(obs.core.nodes[1]?.label, 'OK');
      await session.end();
    });
  });

  group('DefaultLoopHost.executeAction', () {
    test('executeAction delegates to VmServiceClient and returns the '
        'response verbatim', () async {
      String? lastTool;
      Map<String, dynamic>? lastArgs;
      final vm = _fakeVm(
        executeActionHandler: (args) async {
          lastTool = args?['name'] as String?;
          lastArgs = (args?['args'] as Map?)?.cast<String, dynamic>();
          return <String, dynamic>{'ok': true, 'echo': lastTool};
        },
      );
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      final result = await host.executeAction(
        'core.tap',
        const <String, dynamic>{'id': 42},
      );
      expect(lastTool, 'core.tap');
      expect(lastArgs, equals(<String, dynamic>{'id': 42}));
      expect(result, equals(<String, dynamic>{'ok': true, 'echo': 'core.tap'}));

      await session.end();
    });

    test('non-transport RPCError propagates unwrapped', () async {
      final vm = _FakeVmService((method, args) async {
        if (method == 'ext.flutter.exploration.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        // Method-level failure (extension reported its own error). Code
        // is outside the transport set and message is plain.
        throw RPCError('callServiceExtension', 100, 'application error');
      });
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      await expectLater(
        host.executeAction('core.tap', const <String, dynamic>{}),
        throwsA(isA<RPCError>()
            .having((e) => e.code, 'code', 100)
            .having((e) => e.message, 'message', 'application error')),
      );
      await session.end();
    });
  });

  group('DefaultLoopHost.notifyPlugins no-op', () {
    test('notifyPlugins completes without contacting the VM service',
        () async {
      int extraCalls = 0;
      final vm = _FakeVmService((method, args) async {
        if (method == 'ext.flutter.exploration.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        extraCalls++;
        return _resp(<String, dynamic>{});
      });
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      await host.notifyPlugins(
        'core.tap',
        const <String, dynamic>{'id': 1},
        const <String, dynamic>{'ok': true},
      );
      expect(extraCalls, 0,
          reason:
              'notifyPlugins must not issue any VM-service calls; the '
              'binding fires PluginRegistry.onActionExecutedAll in-process '
              'during executeAction.');
      await session.end();
    });
  });

  group('DefaultLoopHost — transport translation', () {
    test('observe: RPCError(-32000, "Service connection disposed") → '
        'VmServiceConnectionLost', () async {
      final vm = _FakeVmService((method, args) async {
        if (method == 'ext.flutter.exploration.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        throw RPCError(
          'callServiceExtension',
          -32000,
          'Service connection disposed',
        );
      });
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      await expectLater(
        host.observe(),
        throwsA(isA<VmServiceConnectionLost>()),
      );
      await session.end();
    });

    test('executeAction: RPCError(-32603, "connection closed") → '
        'VmServiceConnectionLost', () async {
      final vm = _FakeVmService((method, args) async {
        if (method == 'ext.flutter.exploration.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        throw RPCError(
          'callServiceExtension',
          -32603,
          'connection closed',
        );
      });
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      await expectLater(
        host.executeAction('core.tap', const <String, dynamic>{}),
        throwsA(isA<VmServiceConnectionLost>()),
      );
      await session.end();
    });

    test('observe: bare StateError("disposed") from VmService → '
        'VmServiceConnectionLost', () async {
      final vm = _FakeVmService((method, args) async {
        if (method == 'ext.flutter.exploration.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        // VmService throws a bare StateError after dispose() — the host
        // must translate this too.
        throw StateError('disposed');
      });
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.tap')],
        pluginTools: const <String, List<ToolDescriptor>>{},
        goal: 'g',
        agentsMd: 'a',
      );

      await expectLater(
        host.observe(),
        throwsA(isA<VmServiceConnectionLost>()),
      );
      await expectLater(
        host.executeAction('core.tap', const <String, dynamic>{}),
        throwsA(isA<VmServiceConnectionLost>()),
      );
      await session.end();
    });
  });

  group('DefaultLoopHost integration with LoopDriver', () {
    test('driver writes one plugin_disabled record per auto-disabled '
        'namespace via TrajectoryWriter', () async {
      // Three turns where the binding fragment for namespace `flaky`
      // reports `error`. The driver's plugin-failure tracker should
      // strike out at threshold 3 and emit exactly one
      // PluginDisabledEvent via the writer.
      final vm = _fakeVm(
        plugins: <Map<String, dynamic>>[
          <String, dynamic>{
            'namespace': 'flaky',
            'tools': <String>['flaky.x'],
          },
        ],
        observationHandler: (args) async => <String, dynamic>{
          'value': <String, dynamic>{
            'semantics': <Map<String, dynamic>>[],
            'routes': <String>['/'],
            'errors': <Map<String, dynamic>>[],
            'plugins': <String, dynamic>{
              'flaky': <String, dynamic>{'error': 'boom'},
            },
            'stability': <String, dynamic>{
              'policy': 'action_relative',
              'terminated_by': 'all_idle',
              'duration_ms': 0,
              'framework_busy': <String, dynamic>{},
              'plugins_busy': <Map<String, dynamic>>[],
            },
          },
        },
      );
      final session = await _newStartedSession(vm);
      final host = DefaultLoopHost.fromSession(
        session: session,
        coreTools: <ToolDescriptor>[_tool('core.wait')],
        pluginTools: <String, List<ToolDescriptor>>{
          'flaky': <ToolDescriptor>[_tool('flaky.x')],
        },
        goal: 'g',
        agentsMd: 'a',
      );

      final sink = _MemorySink();
      final writer = TrajectoryWriter(sink);
      await writer.writeHeader(const SessionHeader(
        goal: 'g',
        agentsMdHash: 'h',
        buildIdentifier: 'build',
        modelIdentifier: 'fake',
        harnessVersion: '0.1',
        plugins: <PluginManifestRecord>[],
        config: <String, dynamic>{},
      ));

      final provider = _FakeProvider(
        ModelDecision(
          action: (tool: 'core.wait', args: const <String, dynamic>{}),
        ),
      );

      final term = await session.run(
        host: host,
        provider: provider,
        writer: writer,
      );

      // Count plugin_disabled records in the trajectory sink.
      final pluginDisabled = sink.lines
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .where((r) => r['type'] == 'plugin_disabled')
          .toList();
      expect(pluginDisabled, hasLength(1),
          reason:
              'Exactly one plugin_disabled record per auto-disabled '
              'namespace.');
      expect(pluginDisabled.single['namespace'], 'flaky');

      // Driver still ran (turns continue after auto-disable). The
      // session terminates with budget_exhausted because the canned
      // observation never reports core.done.
      expect(term.outcome, isNot(SessionOutcome.harnessError));

      await session.end();
    });
  });
}
