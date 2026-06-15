/// `ModelProvider` for GPT-5-class models via OpenAI's HTTP Chat
/// Completions tools API.
///
/// Web-compatible: HTTP via `package:http`, no `dart:io`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../action_schema.dart';
import '../model_provider.dart';
import '../types.dart';
import 'openai_models.dart';
import 'openai_parse.dart';
import 'openai_request.dart';

/// `ModelProvider` for GPT-5-class models. Frontier-tier defaults are
/// applied per [FrontierDefaults]; retry-once on schema rejection is
/// enforced inside [decide] (per .18's contract for frontier providers
/// that issue an HTTP round-trip per turn).
class OpenAiModelProvider implements ModelProvider {
  /// Build an [OpenAiModelProvider].
  ///
  /// [endpoint] defaults to `https://api.openai.com/v1/chat/completions`.
  /// [client] defaults to a fresh `http.Client()`.
  OpenAiModelProvider({
    required this.modelId,
    required this.apiKey,
    Uri? endpoint,
    http.Client? client,
  })  : endpoint = endpoint ??
            Uri.parse('https://api.openai.com/v1/chat/completions'),
        _client = client ?? http.Client();

  /// OpenAI model id (e.g. `gpt-5`).
  final String modelId;

  /// OpenAI API key, sent in the `Authorization: Bearer ...` header.
  final String apiKey;

  /// Chat completions endpoint.
  final Uri endpoint;

  final http.Client _client;
  final StreamController<ThinkingDelta> _thinking =
      StreamController<ThinkingDelta>.broadcast();

  @override
  ModelCapabilities get capabilities {
    final OpenAiModel? m = openAiModels[modelId];
    if (m == null) {
      throw ArgumentError('unknown OpenAI model: $modelId');
    }
    return m.capabilities;
  }

  @override
  Stream<ThinkingDelta> thinking() => _thinking.stream;

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    try {
      return await _attempt(snapshot, schema, null);
    } on SchemaRejection catch (e) {
      return await _attempt(snapshot, schema, e.validationError);
    }
  }

  Future<ModelDecision> _attempt(
    ConversationSnapshot snapshot,
    ActionSchema schema,
    String? schemaErrorNote,
  ) async {
    final Map<String, dynamic> body = buildOpenAiRequest(
      model: modelId,
      snapshot: snapshot,
      schema: schema,
      visionEnabled: capabilities.vision,
      schemaErrorNote: schemaErrorNote,
    );

    final http.Response res = await _client.post(
      endpoint,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode >= 400) {
      throw StateError('openai http ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> decoded =
        (jsonDecode(res.body) as Map).cast<String, dynamic>();
    // OpenAI elides thinking from history — parseOpenAiResponse may pick
    // up rationale / wait_strategy sibling JSON; thinking stays null.
    final ModelDecision parsed =
        parseOpenAiResponse(decoded, schema: schema, tools: snapshot.tools);
    return ModelDecision(
      action: parsed.action,
      thinking: null,
      rationale: parsed.rationale,
      waitStrategy: parsed.waitStrategy,
      providerRequestId: parsed.providerRequestId,
    );
  }

  /// Stream incremental `delta.content` chunks from the SSE chat
  /// completions endpoint into [thinking]. Terminates when the server
  /// emits `data: [DONE]`, at which point a final `isFinal: true` delta
  /// is published.
  Future<void> streamThinking(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final Map<String, dynamic> body = buildOpenAiRequest(
      model: modelId,
      snapshot: snapshot,
      schema: schema,
      visionEnabled: capabilities.vision,
      stream: true,
    );

    final http.Request req = http.Request('POST', endpoint)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..body = jsonEncode(body);

    final http.StreamedResponse res = await _client.send(req);
    await for (final String line in res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final String payload = line.substring(6).trim();
      if (payload == '[DONE]') {
        _thinking.add(const ThinkingDelta(text: '', isFinal: true));
        return;
      }
      final Map<String, dynamic> chunk =
          (jsonDecode(payload) as Map).cast<String, dynamic>();
      final List<dynamic>? choices = chunk['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) continue;
      final Map<String, dynamic>? delta =
          ((choices.first as Map)['delta'] as Map?)?.cast<String, dynamic>();
      final String? text = delta?['content'] as String?;
      if (text != null && text.isNotEmpty) {
        _thinking.add(ThinkingDelta(text: text, isFinal: false));
      }
    }
  }

  /// Release resources — closes the broadcast thinking stream and the
  /// underlying HTTP client.
  Future<void> close() async {
    await _thinking.close();
    _client.close();
  }
}
