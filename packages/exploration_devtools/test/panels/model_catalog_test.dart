import 'dart:convert';

import 'package:exploration_devtools/src/panels/model_catalog.dart';
import 'package:exploration_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Anthropic', () {
    test('fetch parses display_name + merges vision capability', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/v1/models');
        expect(req.headers['x-api-key'], 'k');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'claude-sonnet-4-6',
                'display_name': 'Claude Sonnet 4.6',
              },
              <String, dynamic>{
                'id': 'claude-haiku-4-text',
                'display_name': 'Claude Haiku 4 Text',
              },
            ],
          }),
          200,
        );
      });
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(AnthropicUiConfig(apiKey: 'k'));
      expect(models, hasLength(2));
      expect(models[0].id, 'claude-sonnet-4-6');
      expect(models[0].label, 'Claude Sonnet 4.6');
      expect(models[0].capabilities?.vision, isTrue);
      expect(models[1].capabilities, isNull); // unknown caps
    });

    test('401 surfaces ModelCatalogError', () async {
      final client =
          MockClient((req) async => http.Response('unauth', 401));
      final catalog = ModelCatalog(client: client);
      await expectLater(
        catalog.fetch(AnthropicUiConfig(apiKey: 'k')),
        throwsA(isA<ModelCatalogError>()
            .having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('cache hit avoids second network call', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonEncode({'data': <Map<String, dynamic>>[]}), 200);
      });
      final catalog = ModelCatalog(client: client);
      final cfg = AnthropicUiConfig(apiKey: 'k');
      await catalog.fetch(cfg);
      await catalog.fetch(cfg);
      expect(calls, 1);
      await catalog.fetch(cfg, reload: true);
      expect(calls, 2);
    });
  });

  group('OpenAI', () {
    test('fetch parses ids and merges caps', () async {
      final client = MockClient((req) async {
        expect(req.headers['authorization'], 'Bearer k');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'object': 'list',
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'gpt-5'},
              <String, dynamic>{'id': 'gpt-3'},
            ],
          }),
          200,
        );
      });
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(OpenAiUiConfig(apiKey: 'k'));
      expect(models, hasLength(2));
      expect(models[0].id, 'gpt-5');
      expect(models[0].capabilities?.vision, isTrue);
      expect(models[1].capabilities, isNull);
    });

    test('401 surfaces ModelCatalogError', () async {
      final client = MockClient((req) async => http.Response('', 401));
      final catalog = ModelCatalog(client: client);
      await expectLater(
        catalog.fetch(OpenAiUiConfig(apiKey: 'k')),
        throwsA(isA<ModelCatalogError>()),
      );
    });
  });

  group('swift-infer', () {
    test('GET sets Bearer + conversation + capture-bodies + content-type',
        () async {
      Map<String, String>? captured;
      final client = MockClient((req) async {
        captured = Map<String, String>.from(req.headers);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'qwen3.6-35b-a3b-8bit'},
            ],
          }),
          200,
        );
      });
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        captureBodies: true,
      );
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(cfg, conversationId: 'conv-1');
      expect(captured!['authorization'], 'Bearer tok');
      expect(captured!['x-conversation-id'], 'conv-1');
      expect(captured!['x-swift-infer-capture-bodies'], 'true');
      expect(captured!.containsKey('x-api-key'), isFalse);
      expect(models.single.id, 'qwen3.6-35b-a3b-8bit');
      expect(models.single.capabilities?.preserveThinking, isTrue);
    });

    test('404 falls back to defaultModelId', () async {
      final client = MockClient((req) async => http.Response('not found', 404));
      final cfg = SwiftInferUiConfig(
        bearerToken: 't',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(cfg);
      expect(models, hasLength(1));
      expect(models.single.id, cfg.defaultModelId);
      expect(models.single.usingFallback, isTrue);
    });

    test('network exception falls back', () async {
      final client = MockClient((req) async => throw Exception('boom'));
      final cfg = SwiftInferUiConfig(
        bearerToken: 't',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(cfg);
      expect(models.single.usingFallback, isTrue);
    });

    test('500 falls back instead of throwing', () async {
      final client = MockClient((req) async => http.Response('bad', 503));
      final cfg = SwiftInferUiConfig(
        bearerToken: 't',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      final catalog = ModelCatalog(client: client);
      final models = await catalog.fetch(cfg);
      expect(models.single.usingFallback, isTrue);
    });

    test('401 still throws ModelCatalogError (auth failure is actionable)',
        () async {
      final client = MockClient((req) async => http.Response('unauth', 401));
      final cfg = SwiftInferUiConfig(
        bearerToken: 'bad',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      final catalog = ModelCatalog(client: client);
      await expectLater(
        catalog.fetch(cfg),
        throwsA(isA<ModelCatalogError>()
            .having((e) => e.statusCode, 'status', 401)),
      );
    });
  });
}
