/// Provider-factory defaults per PRD §16.4 (per-tier defaults).
///
/// The qwen-mlx tier in particular must default vision *on* per PRD
/// §16.3 ("Qwen3.6-35B-A3B is image-text-to-text. Screenshots are a
/// first-class input modality, not an optional fallback. We default
/// screenshots **on** for the exploration agent."). The underlying
/// `SwiftInferConfig` ships with `enableVision: false`, so the CLI must
/// override it explicitly — we assert that here so a future refactor
/// cannot silently regress to text-only.
library;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_cli/src/cli_args.dart';
import 'package:exploration_cli/src/provider_factory.dart';
import 'package:test/test.dart';

void main() {
  group('buildProvider', () {
    test('qwen-mlx defaults vision ON (PRD §16.3)', () {
      final ModelProvider p = buildProvider(ModelTier.qwenMlx);
      expect(p, isA<SwiftInferModelProvider>());
      expect(
        p.capabilities.vision,
        isTrue,
        reason: 'PRD §16.3 defaults screenshots ON for Qwen3.6 VLM',
      );
      expect(
        p.capabilities.preserveThinking,
        isTrue,
        reason: 'PRD §16.3 enables preserve_thinking by default',
      );
      expect(p.capabilities.supportsToolUse, isTrue);
    });
  });
}
