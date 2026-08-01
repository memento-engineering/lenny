import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:leonard_devtools/src/panels/provider_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryProviderConfigStore', () {
    test('round-trip preserves swift-infer config', () async {
      final store = InMemoryProviderConfigStore();
      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        captureBodies: false,
        extraHeaders: const {'x-a': 'b'},
      );
      await store.save(cfg);
      final loaded = await store.load('swift-infer') as SwiftInferUiConfig;
      expect(loaded.bearerToken, 'tok');
      expect(loaded.endpoint, cfg.endpoint);
      expect(loaded.captureBodies, isFalse);
      expect(loaded.extraHeaders, equals({'x-a': 'b'}));
    });

    test('missing key returns null', () async {
      final store = InMemoryProviderConfigStore();
      expect(await store.load('anthropic'), isNull);
    });

    test('save overwrites previous entry', () async {
      final store = InMemoryProviderConfigStore();
      await store.save(AnthropicUiConfig(apiKey: 'one'));
      await store.save(AnthropicUiConfig(apiKey: 'two'));
      final loaded = await store.load('anthropic') as AnthropicUiConfig;
      expect(loaded.apiKey, 'two');
    });
  });

  group('DtdProviderConfigStore', () {
    test('round-trip via callbacks; missing → null', () async {
      final cells = <String, String>{};
      final store = DtdProviderConfigStore(
        read: (k) async => cells[k],
        write: (k, v) async => cells[k] = v,
      );
      final cfg = AnthropicUiConfig(
        apiKey: 'k',
        baseUrlOverride: Uri.parse('https://my-proxy.example.com'),
      );
      await store.save(cfg);
      expect(cells['lenny.providerConfig.anthropic'], isNotNull);
      // Token persisted unredacted (workspace-local).
      expect(cells['lenny.providerConfig.anthropic']!.contains('"k"'), isTrue);

      final loaded = await store.load('anthropic') as AnthropicUiConfig;
      expect(loaded.apiKey, 'k');
      expect(loaded.baseUrlOverride.toString(), 'https://my-proxy.example.com');

      expect(await store.load('swift-infer'), isNull);
    });

    test('per-provider keys are independent', () async {
      final cells = <String, String>{};
      final store = DtdProviderConfigStore(
        read: (k) async => cells[k],
        write: (k, v) async => cells[k] = v,
      );
      await store.save(AnthropicUiConfig(apiKey: 'A'));
      await store.save(OpenAiUiConfig(apiKey: 'O'));
      expect((await store.load('anthropic') as AnthropicUiConfig).apiKey, 'A');
      expect((await store.load('openai') as OpenAiUiConfig).apiKey, 'O');
    });

    test(
      'null-connection callbacks: read returns null, write is a no-op',
      () async {
        // Mirrors main.dart production callbacks when dtdManager.connection.value
        // is null (standalone web / simulated env with no real DTD connection).
        final store = DtdProviderConfigStore(
          read: (_) async => null,
          write: (_, __) async {},
        );
        await store.save(AnthropicUiConfig(apiKey: 'k'));
        expect(await store.load('anthropic'), isNull);
      },
    );
  });
}
