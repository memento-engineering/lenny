/// Model-id resolution for the CLI provider factory.
///
/// `SWIFT_INFER_MODEL` makes the qwen-mlx tier point at any node the gateway
/// serves; `--model-id` outranks it. Every env read goes through an injected
/// map so these are pure tests — the fake IS the map (house rule: Fakes, not
/// mocks).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_cli/src/cli_args.dart';
import 'package:leonard_cli/src/provider_factory.dart';
import 'package:test/test.dart';

const String _kDefaultQwen = 'qwen3.6-35b-a3b-8bit';
const String _kQwen38 = 'qwen3.8-40b-a3b-8bit';

DartanticModelProvider _qwen({
  Map<String, String> environment = const <String, String>{},
  String? modelId,
}) =>
    buildProvider(
          ModelTier.qwenMlx,
          sessionId: 'sess-1',
          now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
          environment: environment,
          modelId: modelId,
        )
        as DartanticModelProvider;

void main() {
  group('qwen-mlx model id', () {
    test('falls back to the constant when SWIFT_INFER_MODEL is absent', () {
      expect(_qwen().model, _kDefaultQwen);
    });

    test('treats an empty SWIFT_INFER_MODEL as unset', () {
      expect(
        _qwen(environment: <String, String>{'SWIFT_INFER_MODEL': ''}).model,
        _kDefaultQwen,
      );
    });

    test('SWIFT_INFER_MODEL overrides the constant', () {
      expect(
        _qwen(
          environment: <String, String>{'SWIFT_INFER_MODEL': _kQwen38},
        ).model,
        _kQwen38,
      );
    });

    test('--model-id outranks SWIFT_INFER_MODEL', () {
      expect(
        _qwen(
          environment: <String, String>{'SWIFT_INFER_MODEL': _kDefaultQwen},
          modelId: _kQwen38,
        ).model,
        _kQwen38,
      );
    });

    test('capabilities track the resolved id (qwen3.8 keeps qwen caps)', () {
      final DartanticModelProvider p = _qwen(
        environment: <String, String>{'SWIFT_INFER_MODEL': _kQwen38},
      );
      expect(p.capabilities.vision, isTrue);
      expect(p.capabilities.preserveThinking, isTrue);
      expect(p.capabilities.maxContext, 128000);
      expect(p.capabilities.supportsToolUse, isTrue);
    });

    test('endpoint, token and conversation headers are unchanged', () {
      final DartanticModelProvider p = _qwen(
        environment: <String, String>{
          'SWIFT_INFER_ENDPOINT': 'http://host:9999',
          'SWIFT_INFER_AGENT_TOKEN': 'tok',
        },
      );
      final SwiftInferBackend backend = p.backend as SwiftInferBackend;
      expect(backend.baseUrl, Uri.parse('http://host:9999'));
      expect(backend.bearerToken, 'tok');
      expect(
        backend.headers['X-Conversation-Id'],
        'leonard-sess-1-1700000000000',
      );
      expect(backend.headers['X-Session-Id'], 'sess-1');
      expect(backend.headers['X-Swift-Infer-Capture-Bodies'], 'true');
    });

    test('an empty endpoint falls back to localhost:8080', () {
      final DartanticModelProvider p = _qwen(
        environment: <String, String>{'SWIFT_INFER_ENDPOINT': ''},
      );
      expect(
        (p.backend as SwiftInferBackend).baseUrl,
        Uri.parse('http://localhost:8080'),
      );
    });
  });

  group('frontier tiers', () {
    test('--model-id pins the claude model id and its caps', () {
      final DartanticModelProvider p =
          buildProvider(
                ModelTier.claude,
                sessionId: 'sess-1',
                modelId: 'claude-opus-4-6',
                environment: <String, String>{'ANTHROPIC_API_KEY': 'k'},
              )
              as DartanticModelProvider;
      expect(p.model, 'claude-opus-4-6');
      expect(p.capabilities.vision, isTrue);
    });

    test('claude defaults to sonnet when --model-id is absent', () {
      final DartanticModelProvider p =
          buildProvider(
                ModelTier.claude,
                sessionId: 'sess-1',
                environment: <String, String>{'ANTHROPIC_API_KEY': 'k'},
              )
              as DartanticModelProvider;
      expect(p.model, 'claude-sonnet-4-6');
    });

    test('a missing API key throws LOUDLY through the injected env', () {
      expect(
        () => buildProvider(
          ModelTier.claude,
          sessionId: 'sess-1',
          environment: const <String, String>{},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
