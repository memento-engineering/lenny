import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwiftInferUiConfig', () {
    test('headersFor sets the four well-known headers', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        captureBodies: true,
      );
      final h = cfg.headersFor('conv-1');
      expect(h['authorization'], 'Bearer tok');
      expect(h['x-conversation-id'], 'conv-1');
      expect(h['x-swift-infer-capture-bodies'], 'true');
      expect(h['content-type'], 'application/json');
    });

    test('captureBodies=false omits the header', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        captureBodies: false,
      );
      expect(
        cfg.headersFor('c').containsKey('x-swift-infer-capture-bodies'),
        isFalse,
      );
    });

    test('extraHeaders are merged first; well-known headers win', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        extraHeaders: const {
          'x-extra': 'yes',
          'authorization': 'Bearer should-be-overwritten',
          'x-conversation-id': 'wrong',
        },
      );
      final h = cfg.headersFor('right');
      expect(h['x-extra'], 'yes');
      expect(h['authorization'], 'Bearer tok');
      expect(h['x-conversation-id'], 'right');
    });

    test('empty bearer omits Authorization', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: '',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      expect(cfg.headersFor('c').containsKey('authorization'), isFalse);
    });

    test('toJsonRedacted hides bearer; toString does not leak', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: 'super-secret',
        endpoint: Uri.parse('http://localhost:8080'),
      );
      expect(cfg.toJsonRedacted()['bearerToken'], '<redacted>');
      expect(cfg.toString().contains('super-secret'), isFalse);
    });

    test('round-trip through toJson/fromJson preserves fields', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:9000'),
        captureBodies: false,
        extraHeaders: const {'x-a': 'b'},
        defaultModelId: 'qwen3.6-35b-a3b-8bit',
      );
      final decoded = ProviderConfig.fromJson(cfg.toJson()) as SwiftInferUiConfig;
      expect(decoded.bearerToken, 'tok');
      expect(decoded.endpoint, cfg.endpoint);
      expect(decoded.captureBodies, isFalse);
      expect(decoded.extraHeaders, equals({'x-a': 'b'}));
      expect(decoded.defaultModelId, 'qwen3.6-35b-a3b-8bit');
    });
  });

  group('AnthropicUiConfig', () {
    test('default baseUrl is api.anthropic.com', () {
      final cfg = AnthropicUiConfig(apiKey: 'k');
      expect(cfg.baseUrl.toString(), 'https://api.anthropic.com');
    });

    test('headersFor sets x-api-key + anthropic-version', () {
      final cfg = AnthropicUiConfig(apiKey: 'k');
      final h = cfg.headersFor('ignored');
      expect(h['x-api-key'], 'k');
      expect(h['anthropic-version'], '2023-06-01');
    });

    test('toJsonRedacted hides apiKey; toString does not leak', () {
      final cfg = AnthropicUiConfig(apiKey: 'super-secret');
      expect(cfg.toJsonRedacted()['apiKey'], '<redacted>');
      expect(cfg.toString().contains('super-secret'), isFalse);
    });
  });

  group('OpenAiUiConfig', () {
    test('headersFor sends Bearer apiKey', () {
      final cfg = OpenAiUiConfig(apiKey: 'k');
      expect(cfg.headersFor('')['authorization'], 'Bearer k');
    });

    test('toJsonRedacted hides apiKey; toString does not leak', () {
      final cfg = OpenAiUiConfig(apiKey: 'super-secret');
      expect(cfg.toJsonRedacted()['apiKey'], '<redacted>');
      expect(cfg.toString().contains('super-secret'), isFalse);
    });
  });

  test('ProviderConfig.fromJson rejects unknown id', () {
    expect(
      () => ProviderConfig.fromJson(<String, dynamic>{'id': 'bogus'}),
      throwsArgumentError,
    );
  });
}
