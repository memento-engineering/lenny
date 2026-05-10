/// In-memory [ModelCatalog] that fetches each provider's `/v1/models`
/// endpoint, merges the result against the local capability table,
/// and surfaces capability badges + a swift-infer "using fallback"
/// signal when the gateway does not implement `/v1/models`.
library;

import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart' show ModelCapabilities, capabilitiesFor;
import 'package:http/http.dart' as http;

import 'provider_config.dart';

/// One model surfaced in the panel dropdown.
class ResolvedModel {
  const ResolvedModel({
    required this.id,
    required this.label,
    this.capabilities,
    this.usingFallback = false,
  });

  /// Wire model id (e.g. `'gpt-5'`, `'claude-sonnet-4-6'`).
  final String id;

  /// Human label for the dropdown.
  final String label;

  /// Capabilities resolved via [capabilitiesFor]. `null` when unknown
  /// — UI renders a "⚠ unknown capabilities" badge.
  final ModelCapabilities? capabilities;

  /// `true` when this entry is part of the swift-infer static
  /// fallback (gateway does not implement `/v1/models`).
  final bool usingFallback;
}

/// Thrown by [ModelCatalog.fetch] when an HTTP request fails or the
/// response cannot be parsed. The widget surfaces this as an inline
/// banner without crashing the form.
class ModelCatalogError implements Exception {
  ModelCatalogError({this.statusCode, required this.message});

  /// HTTP status code, or `null` if the failure was network /
  /// parse-level.
  final int? statusCode;

  /// Short, user-facing description (e.g. `'401 Unauthorized'`).
  final String message;

  @override
  String toString() => 'ModelCatalogError($statusCode): $message';
}

/// Fetches and caches the per-provider model list.
///
/// Anthropic + OpenAI: `GET <base>/v1/models` with the configured key;
/// any 4xx/5xx → throws [ModelCatalogError] so the panel banner shows.
///
/// swift-infer: same path + the four well-known headers (Authorization
/// Bearer, X-Conversation-Id, X-Swift-Infer-Capture-Bodies, plus the
/// custom extraHeaders bag). On 404, network error, or parse failure,
/// returns a single-entry fallback `[ResolvedModel(defaultModelId,
/// usingFallback: true)]` because the gateway may not implement
/// `/v1/models`.
///
/// Capability merge happens here via [capabilitiesFor]; unknown
/// (provider, model) pairs → `capabilities: null` → unknown badge.
class ModelCatalog {
  ModelCatalog({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, List<ResolvedModel>> _cache = <String, List<ResolvedModel>>{};

  /// Cache key — provider id + base URL so anthropic-prod vs
  /// anthropic-localhost-mock don't collide.
  String _key(ProviderConfig cfg) => '${cfg.id}|${cfg.baseUrl}';

  /// Fetch models for [cfg]. Uses an in-memory cache; pass
  /// `reload: true` to bypass it.
  Future<List<ResolvedModel>> fetch(
    ProviderConfig cfg, {
    bool reload = false,
    String conversationId = '',
  }) async {
    final key = _key(cfg);
    if (!reload && _cache.containsKey(key)) {
      return _cache[key]!;
    }
    final List<ResolvedModel> resolved;
    switch (cfg) {
      case AnthropicUiConfig():
        resolved = await _fetchAnthropic(cfg, conversationId);
      case OpenAiUiConfig():
        resolved = await _fetchOpenAi(cfg, conversationId);
      case SwiftInferUiConfig():
        resolved = await _fetchSwiftInfer(cfg, conversationId);
    }
    _cache[key] = resolved;
    return resolved;
  }

  Uri _modelsUri(ProviderConfig cfg) => cfg.baseUrl.replace(
        path: cfg.baseUrl.path.endsWith('/')
            ? '${cfg.baseUrl.path}v1/models'
            : '${cfg.baseUrl.path}/v1/models',
      );

  Future<List<ResolvedModel>> _fetchAnthropic(
    AnthropicUiConfig cfg,
    String conversationId,
  ) async {
    final res = await _client.get(_modelsUri(cfg), headers: cfg.headersFor(conversationId));
    if (res.statusCode >= 400) {
      throw ModelCatalogError(
        statusCode: res.statusCode,
        message: 'HTTP ${res.statusCode}',
      );
    }
    final decoded = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    final data = (decoded['data'] as List?) ?? const [];
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .map((m) {
      final id = m['id'] as String;
      final label = (m['display_name'] as String?) ?? id;
      return ResolvedModel(
        id: id,
        label: label,
        capabilities: capabilitiesFor('anthropic', id),
      );
    }).toList();
  }

  Future<List<ResolvedModel>> _fetchOpenAi(
    OpenAiUiConfig cfg,
    String conversationId,
  ) async {
    final res = await _client.get(_modelsUri(cfg), headers: cfg.headersFor(conversationId));
    if (res.statusCode >= 400) {
      throw ModelCatalogError(
        statusCode: res.statusCode,
        message: 'HTTP ${res.statusCode}',
      );
    }
    final decoded = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    final data = (decoded['data'] as List?) ?? const [];
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .map((m) {
      final id = m['id'] as String;
      return ResolvedModel(
        id: id,
        label: id,
        capabilities: capabilitiesFor('openai', id),
      );
    }).toList();
  }

  Future<List<ResolvedModel>> _fetchSwiftInfer(
    SwiftInferUiConfig cfg,
    String conversationId,
  ) async {
    try {
      final res = await _client.get(
        _modelsUri(cfg),
        headers: cfg.headersFor(conversationId),
      );
      if (res.statusCode == 404 || res.statusCode >= 500) {
        return _swiftInferFallback(cfg);
      }
      if (res.statusCode >= 400) {
        throw ModelCatalogError(
          statusCode: res.statusCode,
          message: 'HTTP ${res.statusCode}',
        );
      }
      final decoded = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      final data = (decoded['data'] as List?) ?? const [];
      if (data.isEmpty) return _swiftInferFallback(cfg);
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .map((m) {
        final id = m['id'] as String;
        return ResolvedModel(
          id: id,
          label: (m['display_name'] as String?) ?? id,
          capabilities: capabilitiesFor('swift-infer', id),
        );
      }).toList();
    } on ModelCatalogError {
      rethrow;
    } on Object {
      // Network / parse failure — fall back so the user can still pick
      // their default model.
      return _swiftInferFallback(cfg);
    }
  }

  List<ResolvedModel> _swiftInferFallback(SwiftInferUiConfig cfg) =>
      <ResolvedModel>[
        ResolvedModel(
          id: cfg.defaultModelId,
          label: cfg.defaultModelId,
          capabilities: capabilitiesFor('swift-infer', cfg.defaultModelId),
          usingFallback: true,
        ),
      ];

  /// Clear the in-memory cache. Mostly for tests and tear-down.
  void clearCache() => _cache.clear();
}

/// Snapshot driving the prompt panel's model dropdown.
///
/// The mount layer rebuilds this every time the user edits the
/// [ProviderConfig] or presses the reload button.
class ModelCatalogState {
  const ModelCatalogState({
    this.config,
    this.models = const <ResolvedModel>[],
    this.loading = false,
    this.error,
  });

  /// Active provider config. `null` until the user fills the form.
  final ProviderConfig? config;

  /// Models fetched from the active provider.
  final List<ResolvedModel> models;

  /// `true` while a fetch is in flight.
  final bool loading;

  /// Latest fetch failure (if any). Renders as a banner in the panel.
  final Object? error;

  /// Convenience copy-with for the mount layer.
  ModelCatalogState copyWith({
    ProviderConfig? config,
    List<ResolvedModel>? models,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ModelCatalogState(
        config: config ?? this.config,
        models: models ?? this.models,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}
