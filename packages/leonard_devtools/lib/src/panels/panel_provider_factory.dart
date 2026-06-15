/// Constructs a real [ModelProvider] from a panel-side [ProviderConfig]
/// + selected model id.
///
/// Lives in its own file so [PromptPanelController] can take a
/// `ModelProvider Function(ProviderConfig, String, String)` test seam
/// without dragging in the agent provider package at the controller's
/// API boundary.
library;

import 'package:leonard_agent/leonard_agent.dart';

import 'provider_config.dart';

/// Build a [ModelProvider] for [cfg] + [modelId], scoped to [sessionId].
///
/// Each variant maps to its concrete provider:
///
///   - [SwiftInferUiConfig] → [SwiftInferModelProvider] with a
///     [SwiftInferConfig] carrying the bearer token, capture-bodies
///     flag, extra headers, computed `conversationId`
///     (`'leonard-<sessionId>-<unixms>'`), `sessionId`, and
///     `enableVision` derived from [capabilitiesFor].
///   - [AnthropicUiConfig] → [AnthropicModelProvider].
///   - [OpenAiUiConfig]    → [OpenAiModelProvider].
///
/// Unknown-capability models default to `enableVision: false` and
/// `preserveThinking: false`.
ModelProvider buildPanelProvider(
  ProviderConfig cfg,
  String modelId,
  String sessionId, {
  DateTime Function() now = DateTime.now,
}) {
  switch (cfg) {
    case SwiftInferUiConfig():
      final caps = capabilitiesFor('swift-infer', modelId);
      final conversationId =
          'leonard-$sessionId-${now().millisecondsSinceEpoch}';
      return SwiftInferModelProvider(
        config: SwiftInferConfig(
          baseUrl: cfg.endpoint,
          model: modelId,
          bearerToken: cfg.bearerToken,
          captureBodies: cfg.captureBodies,
          conversationId: conversationId,
          sessionId: sessionId,
          extraHeaders: cfg.extraHeaders,
          enableVision: caps?.vision ?? false,
          preserveThinking: caps?.preserveThinking ?? false,
        ),
      );
    case AnthropicUiConfig():
      return AnthropicModelProvider(
        model: modelId,
        apiKey: cfg.apiKey,
        endpoint: cfg.baseUrlOverride?.resolve('/v1/messages'),
      );
    case OpenAiUiConfig():
      return OpenAiModelProvider(
        modelId: modelId,
        apiKey: cfg.apiKey,
        endpoint: cfg.baseUrlOverride?.resolve('/v1/chat/completions'),
      );
  }
}

/// Type for the controller's provider-builder seam.
typedef PanelProviderFactory =
    ModelProvider Function(
      ProviderConfig cfg,
      String modelId,
      String sessionId,
    );
