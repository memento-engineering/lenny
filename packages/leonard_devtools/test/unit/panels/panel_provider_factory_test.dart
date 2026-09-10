import 'package:dart_service_protocol_shared/dart_service_protocol_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/dtd_acp_model_provider.dart';
import 'package:leonard_devtools/src/panels/panel_provider_factory.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';

SwiftInferChatOptions _optionsFor(
  String modelId, {
  SwiftInferReasoningEffort? reasoningEffort,
  int? maxTokens,
  double? temperature,
  double? presencePenalty,
}) {
  final provider =
      buildPanelProvider(
            SwiftInferUiConfig(
              bearerToken: 'tok',
              endpoint: Uri.parse('http://localhost:8080'),
              reasoningEffort: reasoningEffort,
              maxTokens: maxTokens,
              temperature: temperature,
              presencePenalty: presencePenalty,
            ),
            modelId,
            'sess-1',
            now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
          )
          as DartanticModelProvider;
  return (provider.backend as SwiftInferBackend).options!;
}

void main() {
  group('buildPanelProvider — swift-infer options', () {
    test('qwen3.8 defaults to medium effort and 16384 max tokens', () {
      final o = _optionsFor('qwen3.8-40b-a3b-8bit');
      expect(o.reasoningEffort, SwiftInferReasoningEffort.medium);
      expect(o.maxTokens, 16384);
    });

    test('other ids leave the effort unset', () {
      expect(_optionsFor('qwen3.6-35b-a3b-8bit').reasoningEffort, isNull);
    });

    test('panel values win over the defaults', () {
      final o = _optionsFor(
        'qwen3.8-40b-a3b-8bit',
        reasoningEffort: SwiftInferReasoningEffort.low,
        maxTokens: 2048,
        temperature: 0.7,
        presencePenalty: 0.0,
      );
      expect(o.reasoningEffort, SwiftInferReasoningEffort.low);
      expect(o.maxTokens, 2048);
      expect(o.temperature, 0.7);
      expect(o.presencePenalty, 0.0);
    });

    test('unset panel knobs stay unset on the wire options', () {
      final o = _optionsFor('qwen3.6-35b-a3b-8bit');
      expect(o.temperature, isNull);
      expect(o.presencePenalty, isNull);
      expect(o.topP, isNull);
      expect(o.topK, isNull);
      expect(o.repetitionPenalty, isNull);
    });
  });

  group('buildPanelProvider — ACP', () {
    test('requires the host-side panel client', () {
      expect(
        () => buildPanelProvider(
          const AcpUiConfig(harnessLabel: 'codex-acp', modelId: 'model'),
          'model',
          'session',
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'ACP panel client is unavailable',
          ),
        ),
      );
    });

    test('returns DTD provider for selected harness and model', () async {
      String? openedHarness;
      String? openedModel;
      const Map<String, Object?> capabilities = <String, Object?>{
        'vision': false,
        'preserve_thinking': false,
        'max_context': 128000,
        'supports_tool_use': false,
      };
      final DtdAcpPanelClient client = DtdAcpPanelClient(
        listServices: () async => <ClientServiceInfo>[
          ClientServiceInfo('leonard.acp', <String, ClientServiceMethodInfo>{
            'decide': ClientServiceMethodInfo('decide', capabilities),
            'session/new': ClientServiceMethodInfo(
              'session/new',
              <String, Object?>{
                'harness_labels': <String>['codex-acp'],
              },
            ),
          }),
        ],
        newSession: (harness, model) async {
          openedHarness = harness;
          openedModel = model;
          return <String, Object?>{
            'available_models': <String>[model],
            'current_model_id': model,
          };
        },
        providerBuilder: (caps, readiness) => DtdAcpModelProvider(
          capabilities: caps,
          read: () => const Stream<Map<String, Object?>>.empty(),
          call: (_) async => const <String, Object?>{},
          readiness: readiness,
        ),
      );
      await client.refreshHost();

      final ModelProvider provider = buildPanelProvider(
        const AcpUiConfig(
          harnessLabel: 'codex-acp',
          modelId: 'gpt-5.6-sol[high]',
        ),
        'gpt-5.6-sol[max]',
        'session',
        acpPanelClient: client,
      );
      await Future<void>.delayed(Duration.zero);

      expect(provider, isA<DtdAcpModelProvider>());
      expect(openedHarness, 'codex-acp');
      expect(openedModel, 'gpt-5.6-sol[max]');
    });

    test('HTTP configs remain Dartantic providers', () {
      expect(
        buildPanelProvider(
          AnthropicUiConfig(apiKey: 'key'),
          'claude-sonnet-4-6',
          'session',
        ),
        isA<DartanticModelProvider>(),
      );
      expect(
        buildPanelProvider(OpenAiUiConfig(apiKey: 'key'), 'gpt-5', 'session'),
        isA<DartanticModelProvider>(),
      );
    });
  });
}
