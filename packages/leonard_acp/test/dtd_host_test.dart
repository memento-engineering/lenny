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
  turns: <ConversationTurn>[],
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

  @override
  ModelCapabilities get capabilities => _capabilities;

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    snapshots.add(snapshot);
    schemas.add(schema);
    if (_outcome case final SchemaRejection rejection) throw rejection;
    return _outcome as ModelDecision;
  }

  @override
  Stream<ThinkingDelta> thinking() => thinkingController.stream;

  Future<void> close() => thinkingController.close();
}

class _Registration {
  final Map<String, DTDServiceCallback> callbacks =
      <String, DTDServiceCallback>{};
  final Map<String, Map<String, Object?>> capabilities =
      <String, Map<String, Object?>>{};
  Object? failure;

  Future<void> register(
    String service,
    String method,
    DTDServiceCallback callback, {
    Map<String, Object?>? capabilities,
  }) async {
    if (failure case final Object error) throw error;
    expect(service, 'leonard.acp');
    callbacks[method] = callback;
    this.capabilities[method] = capabilities!;
  }
}

Parameters _decideRequest() => Parameters(
  'leonard.acp.decide',
  <String, Object?>{'snapshot': _snapshot.toJson(), 'schema': _schema.toJson()},
);

Parameters _sessionRequest(String label, String model) => Parameters(
  'leonard.acp.session/new',
  <String, Object?>{'harness_label': label, 'model_id': model},
);

DtdAcpSessionBinding _binding(
  _FakeModelProvider provider, {
  List<String> models = const <String>['model-a', 'model-b'],
  String? current = 'model-a',
  Future<void> Function()? dispose,
}) => DtdAcpSessionBinding(
  provider: provider,
  availableModels: models,
  currentModelId: current,
  dispose: dispose ?? () async {},
);

void main() {
  group('DtdAcpSessionBinding', () {
    test('defensively copies models and disposes once', () async {
      final _FakeModelProvider provider = _FakeModelProvider();
      addTearDown(provider.close);
      final List<String> source = <String>['one'];
      int disposals = 0;
      final DtdAcpSessionBinding binding = _binding(
        provider,
        models: source,
        dispose: () async => disposals++,
      );

      source.add('two');
      expect(binding.availableModels, <String>['one']);
      expect(
        () => binding.availableModels.add('three'),
        throwsUnsupportedError,
      );
      await Future.wait<void>(<Future<void>>[
        binding.dispose(),
        binding.dispose(),
      ]);
      expect(disposals, 1);
    });
  });

  group('DtdAcpHost', () {
    test(
      'registers decision capabilities and catalog-derived labels',
      () async {
        final _Registration registration = _Registration();
        final DtdAcpHost host = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async =>
              throw StateError('not opened'),
          registerService: registration.register,
          postEvent: (_, __, ___) async {},
          capabilities: _capabilities,
        );
        addTearDown(host.dispose);

        expect(await host.start(), isTrue);
        expect(registration.callbacks.keys, <String>['decide', 'session/new']);
        expect(registration.capabilities['decide'], <String, Object?>{
          'vision': true,
          'preserve_thinking': false,
          'max_context': 64000,
          'supports_tool_use': false,
        });
        expect(registration.capabilities['session/new'], <String, Object?>{
          'harness_labels': <String>[
            for (final AcpAgentSpec spec in acpAgentSpecs.values) spec.label,
          ],
        });
      },
    );

    test('refuses decide until a session has been opened', () async {
      final _Registration registration = _Registration();
      final DtdAcpHost host = DtdAcpHost(
        acpAgentSpecs: acpAgentSpecs,
        openSession: (AcpAgentSpec spec) async =>
            throw StateError('not opened'),
        registerService: registration.register,
        postEvent: (_, __, ___) async {},
      );
      addTearDown(host.dispose);
      await host.start();

      await expectLater(
        registration.callbacks['decide']!(_decideRequest()),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'ACP session has not been opened',
          ),
        ),
      );
    });

    test(
      'opens by label, overrides only model, and returns exact keys',
      () async {
        final _Registration registration = _Registration();
        final _FakeModelProvider provider = _FakeModelProvider();
        addTearDown(provider.close);
        late AcpAgentSpec opened;
        final DtdAcpHost host = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async {
            opened = spec;
            return _binding(
              provider,
              models: const <String>['gpt-5.6-sol[high]', 'gpt-5.5[low]'],
              current: 'gpt-5.6-sol[high]',
            );
          },
          registerService: registration.register,
          postEvent: (_, __, ___) async {},
        );
        addTearDown(host.dispose);
        await host.start();

        final AcpAgentSpec catalogSpec = acpAgentSpecs['codex']!;
        expect(
          await registration.callbacks['session/new']!(
            _sessionRequest(catalogSpec.label, 'gpt-5.6-sol[high]'),
          ),
          <String, Object?>{
            'available_models': <String>['gpt-5.6-sol[high]', 'gpt-5.5[low]'],
            'current_model_id': 'gpt-5.6-sol[high]',
          },
        );
        expect(opened.label, catalogSpec.label);
        expect(opened.command, catalogSpec.command);
        expect(opened.args, catalogSpec.args);
        expect(opened.env, catalogSpec.env);
        expect(opened.model, 'gpt-5.6-sol[high]');

        expect(
          await registration.callbacks['decide']!(_decideRequest()),
          <String, Object?>{
            'type': 'ModelDecision',
            'decision': _decision.toJson(),
          },
        );
        expect(provider.snapshots, <ConversationSnapshot>[_snapshot]);
        expect(provider.schemas, <ActionSchema>[_schema]);
      },
    );

    test('keeps factory pin for an empty model id', () async {
      final _Registration registration = _Registration();
      final _FakeModelProvider provider = _FakeModelProvider();
      addTearDown(provider.close);
      late AcpAgentSpec opened;
      final DtdAcpHost host = DtdAcpHost(
        acpAgentSpecs: acpAgentSpecs,
        openSession: (AcpAgentSpec spec) async {
          opened = spec;
          return _binding(provider);
        },
        registerService: registration.register,
        postEvent: (_, __, ___) async {},
      );
      addTearDown(host.dispose);
      await host.start();

      await registration.callbacks['session/new']!(
        _sessionRequest(acpAgentSpecs['codex']!.label, ''),
      );
      expect(opened.model, kCodexPinnedModel);
    });

    test('rejects an unknown harness label', () async {
      final _Registration registration = _Registration();
      final DtdAcpHost host = DtdAcpHost(
        acpAgentSpecs: acpAgentSpecs,
        openSession: (AcpAgentSpec spec) async =>
            throw StateError('must not open'),
        registerService: registration.register,
        postEvent: (_, __, ___) async {},
      );
      addTearDown(host.dispose);
      await host.start();

      await expectLater(
        registration.callbacks['session/new']!(
          _sessionRequest('unknown', 'model'),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            'Unknown ACP harness label: unknown',
          ),
        ),
      );
    });

    test(
      'opens replacement before disposing prior and moves thinking',
      () async {
        final _Registration registration = _Registration();
        final _FakeModelProvider first = _FakeModelProvider();
        final _FakeModelProvider second = _FakeModelProvider();
        addTearDown(first.close);
        addTearDown(second.close);
        final List<String> lifecycle = <String>[];
        final List<String> posts = <String>[];
        int openings = 0;
        final DtdAcpHost host = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async {
            final int index = ++openings;
            lifecycle.add('open$index');
            return _binding(
              index == 1 ? first : second,
              dispose: () async => lifecycle.add('dispose$index'),
            );
          },
          registerService: registration.register,
          postEvent: (stream, kind, data) async {
            expect(stream, 'leonard.acp.thinking');
            expect(kind, 'ThinkingDelta');
            posts.add(data['text']! as String);
          },
        );
        addTearDown(host.dispose);
        await host.start();
        final String label = acpAgentSpecs.values.first.label;

        await registration.callbacks['session/new']!(
          _sessionRequest(label, 'one'),
        );
        first.thinkingController.add(
          const ThinkingDelta(text: 'first', isFinal: false),
        );
        await pumpEventQueue(times: 2);

        await registration.callbacks['session/new']!(
          _sessionRequest(label, 'two'),
        );
        first.thinkingController.add(
          const ThinkingDelta(text: 'stale', isFinal: false),
        );
        second.thinkingController.add(
          const ThinkingDelta(text: 'second', isFinal: true),
        );
        await pumpEventQueue(times: 3);

        expect(lifecycle.take(3), <String>['open1', 'open2', 'dispose1']);
        expect(posts, <String>['first', 'second']);
      },
    );

    test(
      'returns typed rejection and preserves sequential thinking posts',
      () async {
        const SchemaRejection rejection = SchemaRejection(
          validationError: 'args.target is required',
          rawOutput: '{"action":{}}',
        );
        final _Registration registration = _Registration();
        final _FakeModelProvider provider = _FakeModelProvider(
          outcome: rejection,
        );
        addTearDown(provider.close);
        final Completer<void> releaseFirst = Completer<void>();
        final List<String> posts = <String>[];
        final DtdAcpHost host = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async => _binding(provider),
          registerService: registration.register,
          postEvent:
              (String stream, String kind, Map<String, Object?> data) async {
                posts.add(data['text']! as String);
                if (posts.length == 1) await releaseFirst.future;
              },
        );
        addTearDown(host.dispose);
        await host.start();
        await registration.callbacks['session/new']!(
          _sessionRequest(acpAgentSpecs.values.first.label, ''),
        );

        expect(
          await registration.callbacks['decide']!(_decideRequest()),
          <String, Object?>{
            'type': 'SchemaRejection',
            'validation_error': 'args.target is required',
            'raw_output': '{"action":{}}',
          },
        );

        provider.thinkingController
          ..add(const ThinkingDelta(text: 'first', isFinal: false))
          ..add(const ThinkingDelta(text: 'second', isFinal: true));
        await pumpEventQueue(times: 2);
        expect(posts, <String>['first']);
        releaseFirst.complete();
        await pumpEventQueue(times: 3);
        expect(posts, <String>['first', 'second']);
      },
    );

    test(
      'reports duplicate registration and rethrows other RPC errors',
      () async {
        final _Registration duplicate = _Registration()
          ..failure = RpcException(
            RpcErrorCodes.kServiceAlreadyRegistered,
            'already registered',
          );
        final List<String> errors = <String>[];
        final DtdAcpHost duplicateHost = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async =>
              throw StateError('not opened'),
          registerService: duplicate.register,
          postEvent: (_, __, ___) async {},
        );
        expect(await duplicateHost.start(reportError: errors.add), isFalse);
        expect(errors.single, contains('leonard.acp is already registered'));

        final RpcException failure = RpcException(-32602, 'bad');
        final _Registration unrelated = _Registration()..failure = failure;
        final DtdAcpHost unrelatedHost = DtdAcpHost(
          acpAgentSpecs: acpAgentSpecs,
          openSession: (AcpAgentSpec spec) async =>
              throw StateError('not opened'),
          registerService: unrelated.register,
          postEvent: (_, __, ___) async {},
        );
        await expectLater(unrelatedHost.start(), throwsA(same(failure)));
      },
    );
  });

  group('dtd_host executable', () {
    test('exposes exactly the required options and defaults', () {
      final ArgParser parser = executable.buildDtdHostArgParser();

      expect(
        parser.options.keys,
        unorderedEquals(<String>['dtd-uri', 'dtd-secret', 'cwd', 'verbose']),
      );
      expect(parser.options['dtd-uri']!.mandatory, isTrue);
      expect(parser.options['dtd-secret']!.mandatory, isTrue);
      expect(parser.options['agent'], isNull);
      expect(parser.options['cwd']!.defaultsTo, Directory.current.path);
      expect(parser.options['verbose']!.isFlag, isTrue);
    });

    test('wires the shared catalog and host-owned ACP session lifecycle', () {
      final String source = File('bin/dtd_host.dart').readAsStringSync();
      final String hostSource = File(
        'lib/src/dtd_acp_host.dart',
      ).readAsStringSync();
      final String panelSource = File(
        '../leonard_devtools/lib/src/dtd_acp_model_provider.dart',
      ).readAsStringSync();

      expect(source, contains('acpAgentSpecs: acpAgentSpecs'));
      expect(source, contains('AcpSession.start('));
      expect(source, contains('session.newSession('));
      expect(source, contains('session.availableModelIds'));
      expect(source, contains('session.modelId'));
      expect(source, contains('AcpModelProvider(session: session)'));
      expect(source, contains('await dtd.done'));
      expect(source, contains('await host?.dispose()'));
      expect(source, isNot(contains("addOption('agent'")));
      expect(hostSource, isNot(contains('resolveModelId')));
      expect(panelSource, isNot(contains('resolveModelId')));
      expect(source, isNot(contains('dtdSecret)')));
    });
  });
}
