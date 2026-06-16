// Live validation for lenny-4dhv.1: drive the new SwiftInferChatModel against
// the real swift-infer endpoint and confirm thinking deltas + tool-call
// accumulation stream WITHOUT the anthropic_sdk_dart signature crash.
//
// Run: cd packages/leonard_agent && \
//   SWIFT_INFER_AGENT_TOKEN=... dart run tool/live_swift_infer_probe.dart
import 'dart:io';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_model.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_options.dart';

Future<void> main() async {
  final token = Platform.environment['SWIFT_INFER_AGENT_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('SWIFT_INFER_AGENT_TOKEN missing');
    exit(2);
  }

  final tool = Tool(
    name: 'report_status',
    description:
        'Report the result of the check. You MUST call this to answer.',
    inputSchema: S.object(
      properties: {
        'ok': S.boolean(description: 'whether the check passed'),
        'note': S.string(description: 'a short confirmation string'),
      },
      required: ['ok', 'note'],
    ),
    onCall: (args) async => {'ack': true},
  );

  final model = SwiftInferChatModel(
    name: 'qwen3.6-35b-a3b-8bit',
    baseUrl: Uri.parse('http://localhost:8080'),
    bearerToken: token,
    tools: [tool],
    headers: const {
      'x-conversation-id': 'spike-4dhv1',
      'x-session-id': 'spike-4dhv1-live',
    },
    defaultOptions: const SwiftInferChatOptions(
      maxTokens: 3000,
      temperature: 0.7,
    ),
  );

  final messages = [
    ChatMessage.user(
      'Run a quick health check and report the result using the report_status '
      'tool. Set ok=true and note to a short confirmation string.',
    ),
  ];

  var chunks = 0, thinkingChars = 0, textChars = 0;
  String? firstThinking;
  final toolCalls = <String>[];
  String? finish;
  final sw = Stopwatch()..start();

  try {
    await for (final r in model.sendStream(messages)) {
      chunks++;
      for (final p in r.output.parts) {
        if (p is ThinkingPart) {
          thinkingChars += p.text.length;
          firstThinking ??= p.text;
        } else if (p is TextPart) {
          textChars += p.text.length;
        } else if (p is ToolPart && p.kind == ToolPartKind.call) {
          toolCalls.add('${p.toolName}(${p.arguments})');
        }
      }
      if (r.finishReason != FinishReason.unspecified) {
        finish = r.finishReason.name;
      }
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

  stdout.writeln(
    '=== SwiftInferChatModel LIVE — qwen3.6 (${sw.elapsedMilliseconds}ms) ===',
  );
  stdout.writeln('stream chunks : $chunks');
  stdout.writeln(
    '(a) thinking  : $thinkingChars chars  '
    '${thinkingChars > 0 ? "<- PASS (no signature crash)" : "<- NONE"}',
  );
  final ft = firstThinking;
  if (ft != null) stdout.writeln('    head      : ${head(ft)}');
  stdout.writeln('    answer txt: $textChars chars');
  stdout.writeln(
    '(b) toolcalls : ${toolCalls.isEmpty ? "NONE" : "${toolCalls.join("; ")}  <- PASS"}',
  );
  stdout.writeln('(c) finish    : $finish');
}
