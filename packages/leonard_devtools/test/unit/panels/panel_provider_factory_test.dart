import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_agent/leonard_agent.dart';
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
}
