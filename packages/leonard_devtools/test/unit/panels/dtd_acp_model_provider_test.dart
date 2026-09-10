import 'dart:async';
import 'dart:io';

import 'package:dart_service_protocol_shared/dart_service_protocol_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/leonard_devtools.dart';

const Map<String, Object?> _handshake = <String, Object?>{
  'vision': true,
  'preserve_thinking': false,
  'max_context': 128000,
  'supports_tool_use': false,
};

const ToolDescriptor _tool = ToolDescriptor(
  name: 'router.push',
  description: 'Push a route.',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'required': <String>['route'],
    'properties': <String, dynamic>{
      'route': <String, dynamic>{'type': 'string'},
    },
    'additionalProperties': false,
  },
);

const ConversationSnapshot _snapshot = ConversationSnapshot(
  systemMessage: 'Navigate the application.',
  turns: <ConversationTurn>[
    AssistantTurn(
      thinking: 'inspect routes',
      action: (tool: 'router.push', args: <String, dynamic>{'route': '/old'}),
    ),
  ],
  tools: <ToolDescriptor>[_tool],
);

final ActionSchema _schema = ActionSchema.fromToolList(const <ToolDescriptor>[
  _tool,
]);

const ModelDecision _decision = ModelDecision(
  action: (
    tool: 'router.push',
    args: <String, dynamic>{
      'route': '/settings',
      'options': <String, dynamic>{
        'replace': true,
        'tags': <String>['account', 'security'],
      },
    },
  ),
  thinking: 'settings contains the requested control',
  rationale: 'navigate directly',
  waitStrategy: 'idle',
  providerRequestId: 'host-request-9',
  modelMetadata: <String, dynamic>{
    'agent': 'codex',
    'usage': <String, dynamic>{'input_tokens': 42},
  },
);

class _Fixture {
  _Fixture({
    Future<Map<String, Object?>> Function(Map<String, Object?> request)? call,
    Future<void>? readiness,
  }) : call =
           call ??
           ((Map<String, Object?> request) async => <String, Object?>{
             'type': 'ModelDecision',
             'decision': _decision.toJson(),
           }),
       readiness = readiness ?? Future<void>.value();

  final StreamController<Map<String, Object?>> thinking =
      StreamController<Map<String, Object?>>.broadcast();
  final Future<Map<String, Object?>> Function(Map<String, Object?> request)
  call;
  final Future<void> readiness;

  DtdAcpModelProvider provider() => DtdAcpModelProvider(
    capabilities: _handshake,
    read: () => thinking.stream,
    call: call,
    readiness: readiness,
  );

  Future<void> dispose() => thinking.close();
}

ClientServiceInfo _acpService({
  Map<String, Object?>? decideCapabilities = _handshake,
  Object? harnessLabels = const <String>['codex-acp', 'copilot'],
  bool includeDecide = true,
  bool includeSession = true,
}) => ClientServiceInfo('leonard.acp', <String, ClientServiceMethodInfo>{
  if (includeDecide)
    'decide': ClientServiceMethodInfo('decide', decideCapabilities),
  if (includeSession)
    'session/new': ClientServiceMethodInfo('session/new', <String, Object?>{
      'harness_labels': harnessLabels,
    }),
});

DtdAcpPanelClient _panelClient({
  required Future<List<ClientServiceInfo>> Function() listServices,
  Future<Map<String, Object?>> Function(String, String)? newSession,
  DtdAcpProviderBuilder? providerBuilder,
}) => DtdAcpPanelClient(
  listServices: listServices,
  newSession:
      newSession ??
      (String harness, String model) async => <String, Object?>{
        'available_models': <String>['model-a'],
        'current_model_id': 'model-a',
      },
  providerBuilder:
      providerBuilder ??
      (Map<String, Object?> capabilities, Future<void> readiness) =>
          DtdAcpModelProvider(
            capabilities: capabilities,
            read: () => const Stream<Map<String, Object?>>.empty(),
            call: (Map<String, Object?> request) async => <String, Object?>{
              'type': 'ModelDecision',
              'decision': _decision.toJson(),
            },
            readiness: readiness,
          ),
);

void main() {
  group('DtdAcpPanelClient', () {
    test('returns null only when no ACP service is registered', () async {
      final DtdAcpPanelClient client = _panelClient(
        listServices: () async => <ClientServiceInfo>[
          ClientServiceInfo('another.service'),
        ],
      );

      expect(await client.refreshHost(), isNull);
      expect(
        () => client.buildProvider(harnessLabel: 'codex-acp', modelId: ''),
        throwsStateError,
      );
    });

    test('validates and defensively retains the ACP handshake', () async {
      final List<String> labels = <String>['codex-acp', 'copilot'];
      final Map<String, Object?> capabilities = <String, Object?>{
        ..._handshake,
      };
      final DtdAcpPanelClient client = _panelClient(
        listServices: () async => <ClientServiceInfo>[
          _acpService(decideCapabilities: capabilities, harnessLabels: labels),
        ],
      );

      final DtdAcpHostInfo host = (await client.refreshHost())!;
      labels.add('later');
      capabilities['vision'] = false;
      expect(host.harnessLabels, <String>['codex-acp', 'copilot']);
      expect(host.capabilities['vision'], isTrue);
      expect(() => host.harnessLabels.add('nope'), throwsUnsupportedError);
      expect(() => host.capabilities['vision'] = false, throwsUnsupportedError);
    });

    test('rejects incomplete or wrongly typed registrations', () async {
      for (final ClientServiceInfo service in <ClientServiceInfo>[
        _acpService(includeDecide: false),
        _acpService(includeSession: false),
        _acpService(harnessLabels: <Object?>['codex-acp', 7]),
        _acpService(
          decideCapabilities: <String, Object?>{
            ..._handshake,
            'max_context': 'large',
          },
        ),
      ]) {
        final DtdAcpPanelClient client = _panelClient(
          listServices: () async => <ClientServiceInfo>[service],
        );
        await expectLater(client.refreshHost(), throwsFormatException);
      }
    });

    test('sends selected values and strictly decodes session models', () async {
      String? harness;
      String? model;
      final List<String> source = <String>[
        'gpt-5.6-sol[high]',
        'gpt-5.6-sol[max]',
      ];
      final DtdAcpPanelClient client = _panelClient(
        listServices: () async => <ClientServiceInfo>[_acpService()],
        newSession: (String capturedHarness, String capturedModel) async {
          harness = capturedHarness;
          model = capturedModel;
          return <String, Object?>{
            'available_models': source,
            'current_model_id': 'gpt-5.6-sol[high]',
          };
        },
      );

      final DtdAcpSessionModels session = await client.newSession(
        harnessLabel: 'codex-acp',
        modelId: 'gpt-5.6-sol[high]',
      );
      source.add('later');
      expect(harness, 'codex-acp');
      expect(model, 'gpt-5.6-sol[high]');
      expect(session.availableModels, <String>[
        'gpt-5.6-sol[high]',
        'gpt-5.6-sol[max]',
      ]);
      expect(session.currentModelId, 'gpt-5.6-sol[high]');
      expect(() => session.availableModels.add('nope'), throwsUnsupportedError);

      for (final Map<String, Object?> invalid in <Map<String, Object?>>[
        <String, Object?>{'current_model_id': null},
        <String, Object?>{
          'available_models': <Object?>['model', 1],
          'current_model_id': 'model',
        },
        <String, Object?>{
          'available_models': <String>['model'],
          'current_model_id': 1,
        },
      ]) {
        final DtdAcpPanelClient invalidClient = _panelClient(
          listServices: () async => const <ClientServiceInfo>[],
          newSession: (_, __) async => invalid,
        );
        await expectLater(
          invalidClient.newSession(harnessLabel: 'h', modelId: 'm'),
          throwsFormatException,
        );
      }
    });

    test('buildProvider awaits a new session before first decision', () async {
      final Completer<Map<String, Object?>> opened =
          Completer<Map<String, Object?>>();
      bool decided = false;
      Map<String, Object?>? builtCapabilities;
      final DtdAcpPanelClient client = _panelClient(
        listServices: () async => <ClientServiceInfo>[_acpService()],
        newSession: (_, __) => opened.future,
        providerBuilder: (capabilities, readiness) => DtdAcpModelProvider(
          capabilities: capabilities,
          read: () => const Stream<Map<String, Object?>>.empty(),
          call: (request) async {
            decided = true;
            return <String, Object?>{
              'type': 'ModelDecision',
              'decision': _decision.toJson(),
            };
          },
          readiness: readiness,
        ),
      );
      builtCapabilities = (await client.refreshHost())!.capabilities;
      final DtdAcpModelProvider provider = client.buildProvider(
        harnessLabel: 'copilot',
        modelId: 'model-a',
      );

      final Future<ModelDecision> pending = provider.decide(_snapshot, _schema);
      await pumpEventQueue(times: 2);
      expect(decided, isFalse);
      expect(builtCapabilities, _handshake);
      opened.complete(<String, Object?>{
        'available_models': <String>['model-a'],
        'current_model_id': 'model-a',
      });
      expect(await pending, _decision);
      expect(decided, isTrue);
    });
  });

  test('decodes the synchronous capability handshake', () async {
    final _Fixture fixture = _Fixture();
    addTearDown(fixture.dispose);

    final ModelCapabilities capabilities = fixture.provider().capabilities;

    expect(capabilities.vision, isTrue);
    expect(capabilities.preserveThinking, isFalse);
    expect(capabilities.maxContext, 128000);
    expect(capabilities.supportsToolUse, isFalse);
  });

  test('rejects absent or wrongly typed capability fields synchronously', () {
    for (final Map<String, Object?> invalid in <Map<String, Object?>>[
      <String, Object?>{..._handshake}..remove('vision'),
      <String, Object?>{..._handshake, 'preserve_thinking': 'false'},
      <String, Object?>{..._handshake, 'max_context': 128000.0},
      <String, Object?>{..._handshake, 'supports_tool_use': null},
    ]) {
      expect(
        () => DtdAcpModelProvider(
          capabilities: invalid,
          read: () => const Stream<Map<String, Object?>>.empty(),
          call: (Map<String, Object?> request) async =>
              const <String, Object?>{},
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            'Invalid leonard.acp capability handshake',
          ),
        ),
      );
    }
  });

  test('sends exact wire maps and reconstructs the full decision', () async {
    late Map<String, Object?> request;
    final _Fixture fixture = _Fixture(
      call: (Map<String, Object?> captured) async {
        request = captured;
        return <String, Object?>{
          'type': 'ModelDecision',
          'decision': _decision.toJson(),
        };
      },
    );
    addTearDown(fixture.dispose);

    final ModelDecision actual = await fixture.provider().decide(
      _snapshot,
      _schema,
    );

    expect(request, <String, Object?>{
      'snapshot': _snapshot.toJson(),
      'schema': _schema.toJson(),
    });
    expect(actual, _decision);
  });

  test('restores a typed SchemaRejection with both fields', () async {
    final _Fixture fixture = _Fixture(
      call: (Map<String, Object?> request) async => <String, Object?>{
        'type': 'SchemaRejection',
        'validation_error': 'route must be a string',
        'raw_output': '{"route":7}',
      },
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.provider().decide(_snapshot, _schema),
      throwsA(
        isA<SchemaRejection>()
            .having(
              (SchemaRejection error) => error.validationError,
              'validationError',
              'route must be a string',
            )
            .having(
              (SchemaRejection error) => error.rawOutput,
              'rawOutput',
              '{"route":7}',
            ),
      ),
    );
  });

  test('rejects an unknown host response type', () async {
    final _Fixture fixture = _Fixture(
      call: (Map<String, Object?> request) async => <String, Object?>{
        'type': 'Surprise',
      },
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.provider().decide(_snapshot, _schema),
      throwsA(isA<FormatException>()),
    );
  });

  for (final int code in <int>[-32601, 112]) {
    test('translates unavailable RPC code $code', () async {
      final _Fixture fixture = _Fixture(
        call: (Map<String, Object?> request) async {
          throw RpcException(code, 'unavailable');
        },
      );
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.provider().decide(_snapshot, _schema),
        throwsA(
          isA<DtdAcpUnavailable>().having(
            (DtdAcpUnavailable error) => error.message,
            'message',
            'Host-side ACP service leonard.acp/decide is unavailable; start '
                'leonard_acp:dtd_host and try again.',
          ),
        ),
      );
    });
  }

  test('rethrows unrelated RPC errors unchanged', () async {
    final RpcException failure = RpcException(-32602, 'invalid params');
    final _Fixture fixture = _Fixture(
      call: (Map<String, Object?> request) async => throw failure,
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.provider().decide(_snapshot, _schema),
      throwsA(same(failure)),
    );
  });

  test('awaits readiness before making the call', () async {
    final Completer<void> ready = Completer<void>();
    bool called = false;
    final _Fixture fixture = _Fixture(
      readiness: ready.future,
      call: (Map<String, Object?> request) async {
        called = true;
        return <String, Object?>{
          'type': 'ModelDecision',
          'decision': _decision.toJson(),
        };
      },
    );
    addTearDown(fixture.dispose);

    final Future<ModelDecision> pending = fixture.provider().decide(
      _snapshot,
      _schema,
    );
    await pumpEventQueue(times: 2);
    expect(called, isFalse);

    ready.complete();
    expect(await pending, _decision);
    expect(called, isTrue);
  });

  test('reconstructs thinking and supports sequential listeners', () async {
    final _Fixture fixture = _Fixture();
    addTearDown(fixture.dispose);
    final DtdAcpModelProvider provider = fixture.provider();

    final Future<ThinkingDelta> first = provider.thinking().first;
    fixture.thinking.add(<String, Object?>{
      'text': 'inspect',
      'is_final': false,
    });
    expect(await first, const ThinkingDelta(text: 'inspect', isFinal: false));

    final Future<ThinkingDelta> second = provider.thinking().first;
    fixture.thinking.add(<String, Object?>{'text': 'done', 'is_final': true});
    expect(await second, const ThinkingDelta(text: 'done', isFinal: true));
  });

  test('production proxy remains a transport-only web-safe adapter', () {
    final String source = File(
      'lib/src/dtd_acp_model_provider.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("'dart:io'")));
    expect(source, isNot(contains("'package:leonard_acp")));
    expect(source, contains('dtd.call('));
    expect(RegExp(r'\bdtd\s*\.onEvent\(').hasMatch(source), isTrue);
    expect(RegExp(r'\.streamListen\(').allMatches(source), hasLength(1));
    expect(source, contains('final Future<void> streamListen'));
  });
}
