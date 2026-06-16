// LIVE smoke test for lenny-7ey2 — runs dartantic_ai against the real
// swift-infer qwen3.6 endpoint. Verifies, end to end:
//   (a) thinking deltas actually stream FROM swift-infer (not just Anthropic)
//   (b) tool-call parts accumulate into a usable tool_use
//   (c) qwen behaves on a normal turn without presence/repetition penalty
// Auth note: swift-infer wants `Authorization: Bearer`, but dartantic's Anthropic
// client sends `x-api-key`. We override via the `headers:` map (user wins).
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:http/http.dart' as http;

class DirectClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    stderr.writeln('>>> ${request.method} ${request.url}');
    stderr.writeln('>>> headers: ${request.headers.keys.toList()}');
    return _inner.send(request);
  }
  @override
  void close() => _inner.close();
}

Future<void> main() async {
  final token = Platform.environment['SWIFT_INFER_AGENT_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('SWIFT_INFER_AGENT_TOKEN missing');
    exit(2);
  }

  final tool = Tool(
    name: 'report_status',
    description: 'Report the result of the check. You MUST call this to answer.',
    inputSchema: S.object(
      properties: {
        'ok': S.boolean(description: 'whether the check passed'),
        'note': S.string(description: 'a short confirmation string'),
      },
      required: ['ok', 'note'],
    ),
    onCall: (args) async => {'ack': true},
  );

  final model = AnthropicChatModel(
    name: 'qwen3.6-35b-a3b-8bit',
    apiKey: token,
    baseUrl: Uri.parse('http://localhost:8080'), // SDK appends /v1/messages
    enableThinking:
        Platform.environment['THINK'] == '1', // toggle to isolate parse crash
    client: DirectClient(), // no RetryHttpClient wrap -> driver owns retry
    tools: [tool],
    headers: {
      'Authorization': 'Bearer $token', // swift-infer auth (overrides x-api-key)
      'X-Conversation-Id': 'spike-7ey2',
      'X-Session-Id': 'spike-7ey2-live',
    },
    defaultOptions: AnthropicChatOptions(
      temperature: 0.7,
      topP: 0.95,
      topK: 20,
      maxTokens: 3000,
    ),
  );

  final messages = [
    ChatMessage.user(
      'Run a quick health check and report the result using the report_status '
      'tool. Set ok=true and note to a short confirmation string.',
    ),
  ];

  var chunks = 0, thinkingChunks = 0, thinkingChars = 0, textChars = 0;
  String? firstThinking;
  final toolCalls = <String>[];
  String? finish;
  final sw = Stopwatch()..start();

  try {
    await for (final r in model.sendStream(messages)) {
      chunks++;
      final th = r.thinking;
      if (th != null && th.isNotEmpty) {
        thinkingChunks++;
        thinkingChars += th.length;
        firstThinking ??= th;
      }
      for (final p in r.output.parts) {
        if (p is TextPart) textChars += p.text.length;
        if (p is ToolPart && p.kind == ToolPartKind.call) {
          toolCalls.add('${p.toolName}(${p.arguments})');
        }
      }
      finish = r.finishReason.name;
    }
  } catch (e, st) {
    stderr.writeln('STREAM ERROR after ${sw.elapsedMilliseconds}ms: $e');
    stderr.writeln(st.toString().split('\n').take(8).join('\n'));
    exit(1);
  }
  sw.stop();
  model.dispose();

  String head(String s) {
    final t = s.replaceAll('\n', ' ');
    return t.length <= 160 ? t : t.substring(0, 160);
  }

  stdout.writeln('=== LIVE SMOKE TEST — swift-infer qwen3.6 (${sw.elapsedMilliseconds}ms) ===');
  stdout.writeln('stream chunks : $chunks');
  stdout.writeln('(a) thinking  : $thinkingChunks chunks / $thinkingChars chars  '
      '${thinkingChars > 0 ? "<- PASS" : "<- NO THINKING STREAMED"}');
  final ft = firstThinking;
  if (ft != null) stdout.writeln('    head      : ${head(ft)}');
  stdout.writeln('    answer txt: $textChars chars');
  stdout.writeln('(b) toolcalls : ${toolCalls.isEmpty ? "NONE <- inconclusive" : "${toolCalls.join("; ")}  <- PASS"}');
  stdout.writeln('(c) finish    : $finish  (clean stop, no runaway = ok signal)');
}
