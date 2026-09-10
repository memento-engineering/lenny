import 'package:leonard_acp/leonard_acp.dart' show AcpAgentSpec;
import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_cli/src/cli_args.dart';
import 'package:leonard_cli/src/provider_factory.dart';
import 'package:test/test.dart';

class _FakeModelProvider implements ModelProvider {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    vision: false,
    preserveThinking: false,
    maxContext: 1,
    supportsToolUse: false,
  );

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) => throw UnsupportedError('the provider factory fake never decides');

  @override
  Stream<ThinkingDelta> thinking() => const Stream<ThinkingDelta>.empty();
}

void _expectCopiedSpec(AcpAgentSpec actual, AcpAgentSpec expected) {
  expect(actual, isNot(same(expected)));
  expect(actual.label, expected.label);
  expect(actual.command, expected.command);
  expect(actual.args, expected.args);
  expect(actual.env, expected.env);
}

void main() {
  group('ACP harness provider selection', () {
    test(
      'every catalog harness outranks the tier and returns the builder result',
      () async {
        final List<AcpAgentSpec> selected = <AcpAgentSpec>[];
        final Map<String, _FakeModelProvider> fakes =
            <String, _FakeModelProvider>{
              for (final AcpAgentSpec harness in acpHarnesses.values)
                harness.label: _FakeModelProvider(),
            };

        Future<ModelProvider> buildFake(AcpAgentSpec spec) async {
          selected.add(spec);
          return fakes[spec.label]!;
        }

        for (final AcpAgentSpec harness in acpHarnesses.values) {
          final ModelProvider provider = await buildProvider(
            ModelTier.claude,
            sessionId: 'session',
            harness: harness,
            environment: const <String, String>{},
            acpProviderBuilder: buildFake,
          );

          expect(provider, same(fakes[harness.label]));
          final AcpAgentSpec copied = selected.last;
          _expectCopiedSpec(copied, harness);
          expect(copied.model, harness.model);
        }
      },
    );

    test('--model-id replaces each harness model pin unchanged', () async {
      final List<AcpAgentSpec> selected = <AcpAgentSpec>[];
      final _FakeModelProvider fake = _FakeModelProvider();

      Future<ModelProvider> buildFake(AcpAgentSpec spec) async {
        selected.add(spec);
        return fake;
      }

      for (final AcpAgentSpec harness in acpHarnesses.values) {
        final ModelProvider provider = await buildProvider(
          ModelTier.openai,
          sessionId: 'session',
          modelId: 'gpt-5.6-sol',
          harness: harness,
          environment: const <String, String>{},
          acpProviderBuilder: buildFake,
        );

        expect(provider, same(fake));
        _expectCopiedSpec(selected.last, harness);
        expect(selected.last.model, 'gpt-5.6-sol');
      }
    });

    test('an empty model id preserves the factory pin', () async {
      late AcpAgentSpec selected;
      final AcpAgentSpec harness = AcpAgentSpec.codex();

      await buildProvider(
        ModelTier.claude,
        sessionId: 'session',
        modelId: '',
        harness: harness,
        environment: const <String, String>{},
        acpProviderBuilder: (AcpAgentSpec spec) async {
          selected = spec;
          return _FakeModelProvider();
        },
      );

      expect(selected.model, harness.model);
    });

    test('no harness keeps the direct Dartantic provider path', () {
      final ModelProvider provider =
          buildProvider(
                ModelTier.qwenMlx,
                sessionId: 'session',
                environment: const <String, String>{},
              )
              as ModelProvider;

      expect(provider, isA<DartanticModelProvider>());
    });

    test('disposing an injected fake is an idempotent no-op', () async {
      final _FakeModelProvider fake = _FakeModelProvider();

      await disposeProvider(fake);
      await disposeProvider(fake);
    });
  });
}
