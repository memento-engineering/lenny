/// Widget tests for the `prompt.modelsError` banner — verifies the
/// icon + actionable text rendering, the swift-infer "Use fallback
/// model" link, and that the link is suppressed for providers
/// (anthropic / openai) without a documented "always-available"
/// model id.
library;

import 'dart:convert';

import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/prompt_panel.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ModelCatalog _emptyCatalog() => ModelCatalog(
  client: MockClient(
    (req) async => http.Response(
      jsonEncode(<String, dynamic>{'data': <Map<String, dynamic>>[]}),
      200,
    ),
  ),
);

Widget _host({
  required ModelCatalogState state,
  void Function(String)? onUseFallback,
}) => MaterialApp(
  home: Scaffold(
    body: PromptPanel(
      modelsState: state,
      extensions: const [],
      running: false,
      onStart: (_) {},
      onStop: () {},
      onProviderConfigChanged: (_) {},
      onReloadModels: () {},
      catalog: _emptyCatalog(),
      onUseFallback: onUseFallback,
    ),
  ),
);

void main() {
  testWidgets(
    'renders error icon + actionable toString text for networkOrCors',
    (tester) async {
      await tester.pumpWidget(
        _host(
          state: ModelCatalogState(
            error: ModelCatalogError(
              kind: ModelCatalogErrorKind.networkOrCors,
              message: 'Failed to fetch',
              targetUrl: Uri.parse('http://localhost:8080/v1/models'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('CORS'), findsOneWidget);
      expect(find.textContaining('README'), findsOneWidget);
    },
  );

  testWidgets('renders httpError text including status code', (tester) async {
    await tester.pumpWidget(
      _host(
        state: ModelCatalogState(
          error: ModelCatalogError(
            kind: ModelCatalogErrorKind.httpError,
            statusCode: 401,
            message: 'HTTP 401',
            targetUrl: Uri.parse('http://localhost:8080/v1/models'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(find.textContaining('401'), findsOneWidget);
  });

  testWidgets('swift-infer config shows fallback link with defaultModelId', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      _host(
        state: ModelCatalogState(
          config: SwiftInferUiConfig(
            bearerToken: 't',
            endpoint: Uri.parse('http://localhost:8080'),
            defaultModelId: 'qwen3.6-35b-a3b-8bit',
          ),
          error: ModelCatalogError(
            kind: ModelCatalogErrorKind.networkOrCors,
            message: 'x',
            targetUrl: Uri.parse('http://localhost:8080/v1/models'),
          ),
        ),
        onUseFallback: (id) => tapped = id,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('prompt.modelsError.useFallback')),
      findsOneWidget,
    );
    expect(
      find.text('Use fallback model: qwen3.6-35b-a3b-8bit'),
      findsOneWidget,
    );
    // Error banner is in the settings section — open it first.
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('prompt.modelsError.useFallback')),
    );
    await tester.tap(find.byKey(const Key('prompt.modelsError.useFallback')));
    await tester.pump();
    expect(tapped, 'qwen3.6-35b-a3b-8bit');
  });

  testWidgets('anthropic config hides fallback link', (tester) async {
    await tester.pumpWidget(
      _host(
        state: ModelCatalogState(
          config: AnthropicUiConfig(apiKey: 'k'),
          error: ModelCatalogError(
            kind: ModelCatalogErrorKind.httpError,
            statusCode: 401,
            message: 'HTTP 401',
            targetUrl: Uri.parse('https://api.anthropic.com/v1/models'),
          ),
        ),
        onUseFallback: (_) {},
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(
      find.byKey(const Key('prompt.modelsError.useFallback')),
      findsNothing,
    );
  });

  testWidgets('openai config hides fallback link', (tester) async {
    await tester.pumpWidget(
      _host(
        state: ModelCatalogState(
          config: OpenAiUiConfig(apiKey: 'k'),
          error: ModelCatalogError(
            kind: ModelCatalogErrorKind.httpError,
            statusCode: 403,
            message: 'HTTP 403',
            targetUrl: Uri.parse('https://api.openai.com/v1/models'),
          ),
        ),
        onUseFallback: (_) {},
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(
      find.byKey(const Key('prompt.modelsError.useFallback')),
      findsNothing,
    );
  });

  testWidgets('null config hides fallback link', (tester) async {
    // Pre-bootstrap state: no provider config set yet.
    await tester.pumpWidget(
      _host(
        state: ModelCatalogState(
          error: ModelCatalogError(
            kind: ModelCatalogErrorKind.networkOrCors,
            message: 'x',
          ),
        ),
        onUseFallback: (_) {},
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('prompt.modelsError.useFallback')),
      findsNothing,
    );
  });
}
