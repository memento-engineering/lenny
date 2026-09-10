import 'dart:async' show FutureOr;
import 'dart:io' show Directory;

import 'package:leonard_acp/leonard_acp.dart'
    show AcpAgentSpec, AcpModelProvider, AcpSession;
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

class _FakeAcpSession implements AcpSession {
  _FakeAcpSession({this.newSessionFailure});

  final Object? newSessionFailure;
  String? newSessionCwd;
  int disposeCalls = 0;

  @override
  Future<String> newSession({
    required String cwd,
    List<Object?> mcpServers = const <Object?>[],
  }) {
    newSessionCwd = cwd;
    final Object? failure = newSessionFailure;
    return failure == null
        ? Future<String>.value('fake-session')
        : Future<String>.error(failure, StackTrace.current);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test('real ACP builder owns and disposes the started session', () async {
      final AcpAgentSpec harness = AcpAgentSpec.codex();
      final _FakeAcpSession session = _FakeAcpSession();
      late AcpAgentSpec startedSpec;

      final ModelProvider provider = await buildProvider(
        ModelTier.claude,
        sessionId: 'session',
        harness: harness,
        acpSessionStarter: (AcpAgentSpec spec) async {
          startedSpec = spec;
          return session;
        },
      );

      _expectCopiedSpec(startedSpec, harness);
      expect(startedSpec.model, harness.model);
      expect(session.newSessionCwd, Directory.current.path);
      expect(provider, isA<AcpModelProvider>());

      await disposeProvider(provider);
      expect(session.disposeCalls, 1);
      await disposeProvider(provider);
      expect(session.disposeCalls, 1);
    });

    test(
      'real ACP builder classifies setup failures and preserves Errors',
      () async {
        final AcpAgentSpec harness = AcpAgentSpec.codex();
        final Exception startCause = Exception('start failed');

        final AcpProviderConfigurationException startError = await _captureAcp(
          buildProvider(
            ModelTier.claude,
            sessionId: 'session',
            harness: harness,
            acpSessionStarter: (AcpAgentSpec spec) =>
                Future<AcpSession>.error(startCause, StackTrace.current),
          ),
        );
        expect(startError.harnessLabel, harness.label);
        expect(startError.operation, 'start');
        expect(startError.cause, same(startCause));

        final Exception newSessionCause = Exception('newSession failed');
        final _FakeAcpSession failedSession = _FakeAcpSession(
          newSessionFailure: newSessionCause,
        );
        final AcpProviderConfigurationException newSessionError =
            await _captureAcp(
              buildProvider(
                ModelTier.claude,
                sessionId: 'session',
                harness: harness,
                acpSessionStarter: (AcpAgentSpec spec) async => failedSession,
              ),
            );
        expect(newSessionError.harnessLabel, harness.label);
        expect(newSessionError.operation, 'newSession');
        expect(newSessionError.cause, same(newSessionCause));
        expect(failedSession.disposeCalls, 1);

        final TypeError programmingError = TypeError();
        final _FakeAcpSession errorSession = _FakeAcpSession(
          newSessionFailure: programmingError,
        );
        await expectLater(
          buildProvider(
            ModelTier.claude,
            sessionId: 'session',
            harness: harness,
            acpSessionStarter: (AcpAgentSpec spec) async => errorSession,
          ),
          throwsA(same(programmingError)),
        );
        expect(errorSession.disposeCalls, 1);
      },
    );
  });
}

Future<AcpProviderConfigurationException> _captureAcp(
  FutureOr<ModelProvider> result,
) async {
  try {
    await result;
  } on AcpProviderConfigurationException catch (error) {
    return error;
  }
  fail('expected AcpProviderConfigurationException');
}
