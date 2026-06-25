/// AC11 — DefaultLoopHost drives a MultiHostSession via SessionSurface,
/// unchanged; a LeonardSession still satisfies the same fromSession call
/// (compile + run). Proves the loop host needs no MultiHost-specific code
/// beyond the widened param type + the `_session.executeAction` body edit.
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '_fakes.dart';

ToolDescriptor _td(String name) => ToolDescriptor(
  name: name,
  description: name,
  inputSchema: const <String, dynamic>{'type': 'object'},
);

void main() {
  group('DefaultLoopHost over a MultiHostSession (AC11)', () {
    test('mergedTools includes native.*; observe is merged; executeAction '
        'routes native.tap to the native fake', () async {
      final RecordingVmService flutter = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
        observation: <String, dynamic>{
          'extensions': <String, dynamic>{
            'router': <String, dynamic>{'route': '/home'},
          },
        },
      );
      final RecordingVmService native = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('native', <String>['tap']),
        ],
        observation: <String, dynamic>{
          'extensions': <String, dynamic>{
            'native': <String, dynamic>{
              'fields': <String>['Email'],
            },
          },
        },
      );
      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(flutter), clientOver(native)],
      );
      await session.start('goal', const LeonardConfig());

      // SessionSurface — the host is typed against the interface.
      final SessionSurface surface = session;
      final DefaultLoopHost host = DefaultLoopHost.fromSession(
        session: surface,
        coreTools: <ToolDescriptor>[_td('core.tap')],
        extensionTools: <String, List<ToolDescriptor>>{
          'native': <ToolDescriptor>[_td('native.tap')],
        },
        goal: 'goal',
        agentsMd: 'agents',
      );

      // mergedTools surfaces native.* (the native namespace is active in the
      // merged manifest).
      expect(
        host.mergedTools().map((ToolDescriptor t) => t.name),
        containsAll(<String>['core.tap', 'native.tap']),
      );

      // observe() returns the merged observation (both fragments).
      final Observation obs = await host.observe();
      expect(obs.extensions.keys, containsAll(<String>['router', 'native']));

      // executeAction routes native.tap to the native fake.
      await host.executeAction('native.tap', <String, dynamic>{
        'label': 'Email',
      });
      expect(
        native.calls.map((RecordedCall c) => c.method),
        contains('ext.exploration.native.tap'),
      );
      expect(
        flutter.calls.map((RecordedCall c) => c.method),
        isNot(contains('ext.exploration.native.tap')),
      );
    });

    test(
      'a LeonardSession still satisfies fromSession (back-compat)',
      () async {
        final RecordingVmService vm = RecordingVmService(
          extensions: <Map<String, dynamic>>[
            ext('core', <String>['tap']),
          ],
        );
        final LeonardSession single = LeonardSession.forTest(clientOver(vm));
        await single.start('goal', const LeonardConfig());

        // Compiles + runs against the same fromSession signature.
        final DefaultLoopHost host = DefaultLoopHost.fromSession(
          session: single,
          coreTools: <ToolDescriptor>[_td('core.tap')],
          extensionTools: const <String, List<ToolDescriptor>>{},
          goal: 'goal',
          agentsMd: 'agents',
        );
        await host.executeAction('core.tap', <String, dynamic>{'node_id': 1});
        expect(
          vm.calls.map((RecordedCall c) => c.method),
          contains('ext.exploration.core.tap'),
        );
      },
    );
  });
}
