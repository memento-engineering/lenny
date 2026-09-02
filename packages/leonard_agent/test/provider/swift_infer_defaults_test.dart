import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_options.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_defaults.dart';
import 'package:test/test.dart';

void main() {
  group('defaultSwiftInferOptions', () {
    test('qwen3.8 ids default to medium effort and 16384 max tokens', () {
      final o = defaultSwiftInferOptions('qwen3.8-40b-a3b-8bit');
      expect(o.reasoningEffort, SwiftInferReasoningEffort.medium);
      expect(o.maxTokens, kSwiftInferDriverMaxTokens);
      expect(o.maxTokens, 16384);
    });

    test('other ids keep 16384 but leave the effort unset', () {
      final o = defaultSwiftInferOptions('qwen3.6-35b-a3b-8bit');
      expect(o.reasoningEffort, isNull);
      expect(o.maxTokens, 16384);
    });

    test('caller overrides win over both defaults', () {
      final o = defaultSwiftInferOptions(
        'qwen3.8-40b-a3b-8bit',
        maxTokens: 2048,
        reasoningEffort: SwiftInferReasoningEffort.low,
        temperature: 0.2,
        presencePenalty: 0.0,
      );
      expect(o.maxTokens, 2048);
      expect(o.reasoningEffort, SwiftInferReasoningEffort.low);
      expect(o.temperature, 0.2);
      expect(o.presencePenalty, 0.0);
    });

    test('top_p / top_k / repetition penalty are never defaulted', () {
      final o = defaultSwiftInferOptions('qwen3.8-40b-a3b-8bit');
      expect(o.topP, isNull);
      expect(o.topK, isNull);
      expect(o.repetitionPenalty, isNull);
      expect(o.preserveThinking, isTrue);
    });
  });
}
