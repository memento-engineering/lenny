import 'dart:convert';

import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _host({
  required void Function(ProviderConfig) onChanged,
  ProviderConfig? initial,
  String conversationId = 'conv-1',
  ModelCatalog? catalog,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ProviderConfigForm(
          initial: initial,
          onChanged: onChanged,
          conversationId: conversationId,
          catalog: catalog ??
              ModelCatalog(
                client: MockClient(
                  (req) async => http.Response(
                    jsonEncode(<String, dynamic>{'data': <Map<String, dynamic>>[]}),
                    200,
                  ),
                ),
              ),
        ),
      ),
    );

void main() {
  testWidgets('provider selector lists all three ids', (tester) async {
    await tester.pumpWidget(_host(onChanged: (_) {}));
    await tester.pump();
    expect(find.byKey(const Key('providerForm.providerSelect')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    expect(find.text('swift-infer'), findsWidgets);
    expect(find.text('anthropic'), findsOneWidget);
    expect(find.text('openai'), findsOneWidget);
  });

  testWidgets('swift-infer subform: bearer obscured + extras add/remove',
      (tester) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (c) => last = c));
    await tester.pump();

    expect(find.byKey(const Key('providerForm.swift-infer')), findsOneWidget);

    final bearerField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('providerForm.swift-infer.bearer')),
      matching: find.byType(TextField),
    ));
    expect(bearerField.obscureText, isTrue);

    // Conversation id breadcrumb selectable + read-only.
    expect(find.byKey(const Key('providerForm.swift-infer.conversationId')),
        findsOneWidget);
    final crumb = tester.widget<SelectableText>(
      find.byKey(const Key('providerForm.swift-infer.conversationId')),
    );
    expect(crumb.data, contains('conv-1'));

    // CaptureBodies toggle is on by default.
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('providerForm.swift-infer.captureBodies')),
    );
    expect(switchTile.value, isTrue);

    // Add a header.
    await tester.tap(find.byKey(const Key('providerForm.swift-infer.extra.add')));
    await tester.pump();
    expect(find.byKey(const Key('providerForm.swift-infer.extra.0.key')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('providerForm.swift-infer.extra.0.key')),
      'x-a',
    );
    await tester.enterText(
      find.byKey(const Key('providerForm.swift-infer.extra.0.value')),
      'b',
    );
    await tester.pump();

    expect((last! as SwiftInferUiConfig).extraHeaders['x-a'], 'b');

    // Remove.
    await tester.tap(find.byKey(const Key('providerForm.swift-infer.extra.0.remove')));
    await tester.pump();
    expect((last! as SwiftInferUiConfig).extraHeaders, isEmpty);
  });

  testWidgets('switching to anthropic shows obscured api key field',
      (tester) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (c) => last = c));
    await tester.pump();

    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('anthropic').last);
    await tester.pumpAndSettle();

    expect(last, isA<AnthropicUiConfig>());
    final keyField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('providerForm.anthropic.apiKey')),
      matching: find.byType(TextField),
    ));
    expect(keyField.obscureText, isTrue);
  });

  testWidgets('switching to openai shows obscured api key field',
      (tester) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (c) => last = c));
    await tester.pump();

    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai').last);
    await tester.pumpAndSettle();

    expect(last, isA<OpenAiUiConfig>());
    final keyField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('providerForm.openai.apiKey')),
      matching: find.byType(TextField),
    ));
    expect(keyField.obscureText, isTrue);
  });

  testWidgets('Test connection success renders inline status', (tester) async {
    final catalog = ModelCatalog(
      client: MockClient(
        (req) async => http.Response(
          jsonEncode(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'qwen3.6-35b-a3b-8bit'},
            ],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(_host(
      onChanged: (_) {},
      initial: SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
      ),
      catalog: catalog,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('providerForm.testConnection')));
    await tester.pumpAndSettle();

    expect(find.textContaining('OK ('), findsOneWidget);
  });
}
