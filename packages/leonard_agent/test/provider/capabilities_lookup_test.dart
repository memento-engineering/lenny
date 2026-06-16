import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  group('capabilitiesFor', () {
    test('anthropic vision model returns vision-tier caps', () {
      final c = capabilitiesFor('anthropic', 'claude-sonnet-4-6');
      expect(c, isNotNull);
      expect(c!.vision, isTrue);
      expect(c.preserveThinking, isFalse);
      expect(c.maxContext, 200000);
      expect(c.supportsToolUse, isTrue);
    });

    test('anthropic unknown model returns null', () {
      expect(capabilitiesFor('anthropic', 'claude-haiku-4-text'), isNull);
    });

    test('openai known model uses registry caps', () {
      final c = capabilitiesFor('openai', 'gpt-5');
      expect(c, isNotNull);
      expect(c!.vision, isTrue);
      expect(c.supportsToolUse, isTrue);
    });

    test('openai unknown model returns null', () {
      expect(capabilitiesFor('openai', 'gpt-3'), isNull);
    });

    test('swift-infer qwen3 prefix returns qwen-tier caps', () {
      final c = capabilitiesFor('swift-infer', 'qwen3.6-35b-a3b-8bit');
      expect(c, isNotNull);
      expect(c!.vision, isTrue);
      expect(c.preserveThinking, isTrue);
      expect(
        c.maxContext,
        128000,
      ); // aligned to the swift-infer provider (4dhv.4)
      expect(c.supportsToolUse, isTrue);
    });

    test('swift-infer non-qwen model returns null', () {
      expect(capabilitiesFor('swift-infer', 'llama-3'), isNull);
    });

    test('unknown provider returns null', () {
      expect(capabilitiesFor('bogus', 'whatever'), isNull);
    });

    test('kAnthropicVisionModels exported and contains known ids', () {
      expect(kAnthropicVisionModels, contains('claude-sonnet-4-6'));
      expect(kAnthropicVisionModels, contains('claude-opus-4-6'));
    });
  });
}
