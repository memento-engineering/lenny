// Alternative live path for lenny-7ey2: swift-infer also serves the OpenAI
// wire. dartantic's OpenAIProvider exposes baseUrl+headers cleanly. Does the
// OpenAI path stream reasoning + tool calls from swift-infer WITHOUT the
// anthropic_sdk_dart strict-signature crash?
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

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

  final provider = OpenAIProvider(
    apiKey: token,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    headers: {'Authorization': 'Bearer $token'},
  );

  final model = provider.createChatModel(
    name: 'qwen3.6-35b-a3b-8bit',
    tools: [tool],
    enableThinking: Platform.environment['THINK'] == '1',
    temperature: 0.7,
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

  stdout.writeln('=== OPENAI-WIRE LIVE — swift-infer qwen3.6 (${sw.elapsedMilliseconds}ms) ===');
  stdout.writeln('stream chunks : $chunks');
  stdout.writeln('(a) thinking  : $thinkingChunks chunks / $thinkingChars chars  '
      '${thinkingChars > 0 ? "<- PASS" : "<- none surfaced via ChatResult.thinking"}');
  final ft = firstThinking;
  if (ft != null) stdout.writeln('    head      : ${head(ft)}');
  stdout.writeln('    answer txt: $textChars chars');
  stdout.writeln('(b) toolcalls : ${toolCalls.isEmpty ? "NONE" : "${toolCalls.join("; ")}  <- PASS"}');
  stdout.writeln('(c) finish    : $finish');
}
