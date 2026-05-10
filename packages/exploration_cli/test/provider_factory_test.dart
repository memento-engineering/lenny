/// Provider-factory defaults per PRD §16.4 (per-tier defaults).
///
/// The qwen-mlx tier in particular must default vision *on* per PRD
/// §16.3 ("Qwen3.6-35B-A3B is image-text-to-text. Screenshots are a
/// first-class input modality, not an optional fallback. We default
/// screenshots **on** for the exploration agent."). The underlying
/// `SwiftInferConfig` ships with `enableVision: false`, so the CLI must
/// override it explicitly — we assert that here so a future refactor
/// cannot silently regress to text-only.
///
/// We also pin the fs-agent-symmetric wire-contract bits: per-run
/// X-Conversation-Id format, captureBodies default, and
/// SWIFT_INFER_AGENT_TOKEN env-var read.
library;

import 'dart:io' show Platform;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_cli/src/cli_args.dart';
import 'package:exploration_cli/src/provider_factory.dart';
import 'package:test/test.dart';

void main() {
  group('buildProvider', () {
    test('qwen-mlx defaults vision ON (PRD §16.3)', () {
      final ModelProvider p =
          buildProvider(ModelTier.qwenMlx, sessionId: 'sess-1');
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

    test('qwen-mlx: conversationId formed as exploration-<sessionId>-<unixMs>',
        () {
      final SwiftInferModelProvider p = buildProvider(
        ModelTier.qwenMlx,
        sessionId: 'sess-xyz',
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ) as SwiftInferModelProvider;
      expect(p.config.conversationId, 'exploration-sess-xyz-1700000000000');
      expect(p.config.sessionId, 'sess-xyz');
      expect(
        p.config.captureBodies,
        isTrue,
        reason: 'CLI defaults captureBodies=true so /v1/conversations/<id> '
            'returns the captured turn for inspection',
      );
      // bearerToken mirrors SWIFT_INFER_AGENT_TOKEN — the CI shell may or
      // may not have it set; assert the field tracks the env var either
      // way (null/empty → null; non-empty → that exact value).
      final String? envToken = Platform.environment['SWIFT_INFER_AGENT_TOKEN'];
      if (envToken == null || envToken.isEmpty) {
        expect(p.config.bearerToken, isNull);
      } else {
        expect(p.config.bearerToken, envToken);
      }
    });
  });
}
