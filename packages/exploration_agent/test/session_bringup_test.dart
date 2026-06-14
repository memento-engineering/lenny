/// Unit tests for [bringUpSession].
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_agent/src/session_bringup.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake that responds to handshake and start extensions.
class _FakeVm extends VmService {
  _FakeVm() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    if (method == 'ext.exploration.core.handshake') {
      return Response.parse(<String, dynamic>{
        'type': 'exploration.HandshakeResult',
        'contractVersion': '0.1',
        'plugins': <dynamic>[
          <String, dynamic>{
            'namespace': 'router',
            'tools': <dynamic>['go'],
          },
        ],
      })!;
    }
    if (method == 'ext.exploration.core.start') {
      return Response.parse(<String, dynamic>{
        'type': 'exploration.StartResult',
      })!;
    }
    throw UnsupportedError('unexpected: $method');
  }
}

void main() {
  test('bringUpSession returns header built from handshake manifest', () async {
    final ExplorationSession session =
        ExplorationSession.forTest(VmServiceClient.forTest(_FakeVm(), 'fake-isolate'));

    // Caller is responsible for starting the session before bringUpSession.
    await session.start('navigate to /home', const ExplorationConfig());

    final BringUpResult result = await bringUpSession(
      session: session,
      goal: 'navigate to /home',
      policy: StabilityPolicy.actionRelative,
      modelIdentifier: 'test-model',
      buildIdentifier: 'test-build',
      harnessVersion: '0.0.0',
      coreTools: const <ToolDescriptor>[],
      pluginTools: const <String, List<ToolDescriptor>>{},
      agentsMd: '',
      extraConfig: <String, dynamic>{'extra_key': 42},
    );

    expect(result.header.goal, 'navigate to /home');
    expect(result.header.modelIdentifier, 'test-model');
    expect(result.header.buildIdentifier, 'test-build');
    expect(result.header.harnessVersion, '0.0.0');
    expect(result.header.plugins, hasLength(1));
    expect(result.header.plugins.first.namespace, 'router');
    expect(result.header.plugins.first.contractVersion, '0.1');
    expect(result.header.config['extra_key'], 42);
    expect(result.host, isA<DefaultLoopHost>());
  });
}
