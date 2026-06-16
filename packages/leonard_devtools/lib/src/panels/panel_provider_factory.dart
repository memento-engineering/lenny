/// Constructs a real [ModelProvider] from a panel-side [ProviderConfig]
/// + selected model id.
///
/// Lives in its own file so [PromptPanelController] can take a
/// `ModelProvider Function(ProviderConfig, String, String)` test seam
/// without dragging in the agent provider package at the controller's
/// API boundary.
///
/// Post-dartantic-cutover (ADR 0003 / lenny-4dhv.4): every variant maps to a
/// [DartanticModelProvider] over the matching [ModelBackendSpec]:
///   - [SwiftInferUiConfig] → [SwiftInferBackend] (per-session X- headers +
///     bearer; `X-Conversation-Id` = `'leonard-<sessionId>-<unixms>'`).
///   - [AnthropicUiConfig]  → [AnthropicBackend] (baseUrl = bare origin).
///   - [OpenAiUiConfig]     → [OpenAIBackend] (baseUrl = bare origin).
library;

import 'package:leonard_agent/leonard_agent.dart';

import 'provider_config.dart';

/// Conservative capabilities when [capabilitiesFor] doesn't know the
/// (provider, model) pair — vision off, tool use on, generous context.
const ModelCapabilities _defaultCaps = ModelCapabilities(
  vision: false,
  preserveThinking: false,
  maxContext: 128000,
  supportsToolUse: true,
);

/// Build a [ModelProvider] for [cfg] + [modelId], scoped to [sessionId].
ModelProvider buildPanelProvider(
  ProviderConfig cfg,
  String modelId,
  String sessionId, {
  DateTime Function() now = DateTime.now,
}) {
  switch (cfg) {
    case SwiftInferUiConfig():
      final conversationId =
          'leonard-$sessionId-${now().millisecondsSinceEpoch}';
      return DartanticModelProvider(
        backend: SwiftInferBackend(
          baseUrl: cfg.endpoint,
          bearerToken: cfg.bearerToken.isNotEmpty ? cfg.bearerToken : null,
          headers: <String, String>{
            ...cfg.extraHeaders,
            'X-Conversation-Id': conversationId,
            'X-Session-Id': sessionId,
            if (cfg.captureBodies) 'X-Swift-Infer-Capture-Bodies': 'true',
          },
        ),
        model: modelId,
        capabilities: capabilitiesFor('swift-infer', modelId) ?? _defaultCaps,
      );
    case AnthropicUiConfig():
      // baseUrl is a BARE origin — the dartantic Anthropic model appends
      // /v1/messages itself (do NOT pass the /v1/messages suffix). DevTools is
      // a web build, so the chat POST needs the browser-access header for CORS
      // (the old provider attached it; dartantic does not by default).
      return DartanticModelProvider(
        backend: AnthropicBackend(
          apiKey: cfg.apiKey,
          baseUrl: cfg.baseUrlOverride,
          headers: const {'anthropic-dangerous-direct-browser-access': 'true'},
        ),
        model: modelId,
        capabilities: capabilitiesFor('anthropic', modelId) ?? _defaultCaps,
      );
    case OpenAiUiConfig():
      // dartantic's OpenAI client appends only `/chat/completions` to the base,
      // so the base must already include `/v1`. Resolve the override to its
      // `/v1` root (a bare-origin override otherwise loses the /v1 segment).
      return DartanticModelProvider(
        backend: OpenAIBackend(
          apiKey: cfg.apiKey,
          baseUrl: cfg.baseUrlOverride?.resolve('/v1'),
        ),
        model: modelId,
        capabilities: capabilitiesFor('openai', modelId) ?? _defaultCaps,
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
