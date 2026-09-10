import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:leonard_acp/leonard_acp.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '../bin/dtd_host.dart' as executable;

const ModelCapabilities _capabilities = ModelCapabilities(
  vision: true,
  preserveThinking: false,
  maxContext: 64000,
  supportsToolUse: false,
);

const ToolDescriptor _tool = ToolDescriptor(
  name: 'core.tap',
  description: 'Tap a target.',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'required': <String>['target'],
    'properties': <String, dynamic>{
      'target': <String, dynamic>{'type': 'string'},
    },
    'additionalProperties': false,
  },
);

const ConversationSnapshot _snapshot = ConversationSnapshot(
  systemMessage: 'Choose one action.',
  turns: <ConversationTurn>[
    AssistantTurn(
      thinking: 'look',
      action: (tool: 'core.tap', args: <String, dynamic>{'target': 'old'}),
    ),
  ],
  tools: <ToolDescriptor>[_tool],
);

final ActionSchema _schema = ActionSchema.fromToolList(const <ToolDescriptor>[
  _tool,
]);

const ModelDecision _decision = ModelDecision(
  action: (tool: 'core.tap', args: <String, dynamic>{'target': 'new'}),
  thinking: 'found it',
  rationale: 'the target moved',
  waitStrategy: 'frame',
  providerRequestId: 'request-7',
  modelMetadata: <String, dynamic>{'agent': 'codex'},
);

class _FakeModelProvider implements ModelProvider {
  _FakeModelProvider({Object outcome = _decision}) : _outcome = outcome;

  final Object _outcome;
  final StreamController<ThinkingDelta> thinkingController =
      StreamController<ThinkingDelta>.broadcast();
  final List<ConversationSnapshot> snapshots = <ConversationSnapshot>[];
  final List<ActionSchema> schemas = <ActionSchema>[];

  int get calls => snapshots.length;

  @override
  ModelCapabilities get capabilities => _capabilities;

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    snapshots.add(snapshot);
    schemas.add(schema);
    final Object outcome = _outcome;
    if (outcome is SchemaRejection) throw outcome;
    return outcome as ModelDecision;
  }

  @override
  Stream<ThinkingDelta> thinking() => thinkingController.stream;

  Future<void> close() => thinkingController.close();
}

Parameters _request() => Parameters('leonard.acp.decide', <String, Object?>{
  'snapshot': _snapshot.toJson(),
  'schema': _schema.toJson(),
});

void main() {
  group('DtdAcpHost', () {
    test(
      'registers capabilities, decodes, and delegates exactly once',
      () async {
        final _FakeModelProvider provider = _FakeModelProvider();
        addTearDown(provider.close);

        late String service;
        late String method;
        late DTDServiceCallback callback;
        late Map<String, Object?> registeredCapabilities;
        final DtdAcpHost host = DtdAcpHost(
          provider: provider,
          registerService:
              (
                String capturedService,
                String capturedMethod,
                DTDServiceCallback capturedCallback, {
                Map<String, Object?>? capabilities,
              }) async {
                service = capturedService;
                method = capturedMethod;
                callback = capturedCallback;
                registeredCapabilities = capabilities!;
              },
          postEvent:
              (
                String streamId,
                String eventKind,
                Map<String, Object?> eventData,
              ) async {},
        );
        addTearDown(host.dispose);

        expect(await host.start(), isTrue);
        expect(service, 'leonard.acp');
        expect(method, 'decide');
        expect(registeredCapabilities, <String, Object?>{
          'vision': true,
          'preserve_thinking': false,
          'max_context': 64000,
          'supports_tool_use': false,
        });

        expect(await callback(_request()), <String, Object?>{
          'type': 'ModelDecision',
          'decision': _decision.toJson(),
        });
        expect(provider.calls, 1);
        expect(provider.snapshots.single, _snapshot);
        expect(provider.schemas.single, _schema);
      },
    );

    test('returns a typed schema rejection without retrying', () async {
      const SchemaRejection rejection = SchemaRejection(
        validationError: 'args.target is required',
        rawOutput: '{"action":{}}',
      );
      final _FakeModelProvider provider = _FakeModelProvider(
        outcome: rejection,
      );
      addTearDown(provider.close);
      late DTDServiceCallback callback;
      final DtdAcpHost host = DtdAcpHost(
        provider: provider,
        registerService:
            (
              String service,
              String method,
              DTDServiceCallback capturedCallback, {
              Map<String, Object?>? capabilities,
            }) async {
              callback = capturedCallback;
            },
        postEvent:
            (
              String streamId,
              String eventKind,
              Map<String, Object?> eventData,
            ) async {},
      );
      addTearDown(host.dispose);

      await host.start();

      expect(await callback(_request()), <String, Object?>{
        'type': 'SchemaRejection',
        'validation_error': 'args.target is required',
        'raw_output': '{"action":{}}',
      });
      expect(provider.calls, 1);
    });

    test(
      'posts thinking deltas sequentially and disposes idempotently',
      () async {
        final _FakeModelProvider provider = _FakeModelProvider();
        addTearDown(provider.close);
        final Completer<void> releaseFirst = Completer<void>();
        final List<String> startedPosts = <String>[];
        final List<Map<String, Object?>> completedPosts =
            <Map<String, Object?>>[];
        final DtdAcpHost host = DtdAcpHost(
          provider: provider,
          registerService:
              (
                String service,
                String method,
                DTDServiceCallback callback, {
                Map<String, Object?>? capabilities,
              }) async {},
          postEvent:
              (
                String streamId,
                String eventKind,
                Map<String, Object?> eventData,
              ) async {
                startedPosts.add(eventData['text']! as String);
                if (startedPosts.length == 1) await releaseFirst.future;
                expect(streamId, 'leonard.acp.thinking');
                expect(eventKind, 'ThinkingDelta');
                completedPosts.add(eventData);
              },
        );

        await host.start();
        provider.thinkingController
          ..add(const ThinkingDelta(text: 'first', isFinal: false))
          ..add(const ThinkingDelta(text: 'second', isFinal: true));
        await pumpEventQueue(times: 2);

        expect(startedPosts, <String>['first']);
        releaseFirst.complete();
        await pumpEventQueue(times: 4);
        expect(startedPosts, <String>['first', 'second']);
        expect(completedPosts, <Map<String, Object?>>[
          <String, Object?>{'text': 'first', 'is_final': false},
          <String, Object?>{'text': 'second', 'is_final': true},
        ]);

        expect(provider.thinkingController.hasListener, isTrue);
        await host.dispose();
        expect(provider.thinkingController.hasListener, isFalse);
        await host.dispose();
      },
    );

    test('reports duplicate service registration and returns false', () async {
      final _FakeModelProvider provider = _FakeModelProvider();
      addTearDown(provider.close);
      final List<String> errors = <String>[];
      final DtdAcpHost host = DtdAcpHost(
        provider: provider,
        registerService:
            (
              String service,
              String method,
              DTDServiceCallback callback, {
              Map<String, Object?>? capabilities,
            }) async {
              throw RpcException(
                RpcErrorCodes.kServiceAlreadyRegistered,
                'already registered',
              );
            },
        postEvent:
            (
              String streamId,
              String eventKind,
              Map<String, Object?> eventData,
            ) async {},
      );

      expect(await host.start(reportError: errors.add), isFalse);
      expect(errors, <String>[
        'leonard.acp is already registered; stop the existing ACP host before '
            'starting another.',
      ]);
      expect(provider.thinkingController.hasListener, isFalse);
    });

    test('rethrows unrelated registration RPC errors unchanged', () async {
      final _FakeModelProvider provider = _FakeModelProvider();
      addTearDown(provider.close);
      final RpcException failure = RpcException(
        RpcErrorCodes.kServiceMethodAlreadyRegistered,
        'wrong collision',
      );
      final DtdAcpHost host = DtdAcpHost(
        provider: provider,
        registerService:
            (
              String service,
              String method,
              DTDServiceCallback callback, {
              Map<String, Object?>? capabilities,
            }) async {
              throw failure;
            },
        postEvent:
            (
              String streamId,
              String eventKind,
              Map<String, Object?> eventData,
            ) async {},
      );

      await expectLater(host.start(), throwsA(same(failure)));
    });
  });

  group('dtd_host executable', () {
    test('exposes exactly the required options and defaults', () {
      final ArgParser parser = executable.buildDtdHostArgParser();

      expect(
        parser.options.keys,
        unorderedEquals(<String>[
          'dtd-uri',
          'dtd-secret',
          'agent',
          'cwd',
          'verbose',
        ]),
      );
      expect(parser.options['dtd-uri']!.mandatory, isTrue);
      expect(parser.options['dtd-secret']!.mandatory, isTrue);
      expect(parser.options['agent']!.allowed, <String>['codex', 'copilot']);
      expect(parser.options['agent']!.defaultsTo, 'codex');
      expect(parser.options['cwd']!.defaultsTo, Directory.current.path);
      expect(parser.options['verbose']!.isFlag, isTrue);
    });

    test('wires the real ACP provider stack and DTD lifecycle', () {
      final String source = File('bin/dtd_host.dart').readAsStringSync();

      expect(source, contains('AcpAgentSpec.codex()'));
      expect(source, contains('AcpAgentSpec.copilot()'));
      expect(source, contains('AcpSession.start('));
      expect(source, contains('session.newSession('));
      expect(source, contains('AcpModelProvider(session: session)'));
      expect(source, contains('DtdAcpHost.fromDaemon('));
      expect(source, contains('await dtd.done'));
      expect(source, contains('await host?.dispose()'));
      expect(source, contains('await session?.dispose()'));
      expect(source, isNot(contains('dtdSecret)')));
    });
  });
}
