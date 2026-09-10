import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart'
    show SwiftInferReasoningEffort;
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
  List<String> acpHarnessLabels = const <String>[],
}) => MaterialApp(
  home: Scaffold(
    body: ProviderConfigForm(
      initial: initial,
      onChanged: onChanged,
      conversationId: conversationId,
      acpHarnessLabels: acpHarnessLabels,
      catalog:
          catalog ??
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
  testWidgets('ACP is disabled when no host advertises harnesses', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (config) => last = config));
    await tester.pump();

    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    const String label = 'acp — no ACP host is registered';
    final DropdownMenuItem<String> item = tester.widget(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(DropdownMenuItem<String>),
      ),
    );
    expect(item.value, 'acp');
    expect(item.enabled, isFalse);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(last, isNull);
    expect(find.byKey(const Key('providerForm.acp')), findsNothing);
  });

  testWidgets(
    'ACP renders supplied harness values without credential controls',
    (tester) async {
      ProviderConfig? last;
      await tester.pumpWidget(
        _host(
          onChanged: (config) => last = config,
          acpHarnessLabels: const <String>['codex-acp', 'copilot'],
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('acp').last);
      await tester.pumpAndSettle();

      expect(last, isA<AcpUiConfig>());
      expect((last! as AcpUiConfig).harnessLabel, 'codex-acp');
      expect((last! as AcpUiConfig).modelId, isEmpty);
      expect(find.byKey(const Key('providerForm.acp')), findsOneWidget);
      expect(find.byKey(const Key('providerForm.acp.harness')), findsOneWidget);
      expect(find.text('codex-acp'), findsOneWidget);
      expect(
        find.byKey(const Key('providerForm.testConnection')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('providerForm.acp.harness')));
      await tester.pumpAndSettle();
      expect(find.text('copilot'), findsOneWidget);
      await tester.tap(find.text('copilot'));
      await tester.pumpAndSettle();
      expect((last! as AcpUiConfig).harnessLabel, 'copilot');
      expect((last! as AcpUiConfig).modelId, isEmpty);

      for (final String forbidden in <String>[
        'providerForm.acp.apiKey',
        'providerForm.acp.bearer',
        'providerForm.acp.endpoint',
        'providerForm.acp.permission',
        'providerForm.acp.filesystem',
        'providerForm.acp.terminal',
        'providerForm.acp.codex',
        'providerForm.acp.copilot',
      ]) {
        expect(find.byKey(Key(forbidden)), findsNothing);
      }
    },
  );

  testWidgets('provider selector disables direct OpenAI in browsers', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (config) => last = config));
    await tester.pump();
    expect(
      find.byKey(const Key('providerForm.providerSelect')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    expect(find.text('swift-infer'), findsWidgets);
    expect(find.text('anthropic'), findsOneWidget);
    const label =
        'openai — disabled in browsers; use a proxy through Base URL override';
    final openAiItem = tester.widget<DropdownMenuItem<String>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(DropdownMenuItem<String>),
      ),
    );
    expect(openAiItem.value, 'openai');
    expect(openAiItem.enabled, isFalse);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    expect(last, isNull);
    expect(find.byKey(const Key('providerForm.swift-infer')), findsOneWidget);
    expect(find.byKey(const Key('providerForm.openai')), findsNothing);
  });

  testWidgets('swift-infer subform: bearer obscured + extras add/remove', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (c) => last = c));
    await tester.pump();

    expect(find.byKey(const Key('providerForm.swift-infer')), findsOneWidget);

    final bearerField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('providerForm.swift-infer.bearer')),
        matching: find.byType(TextField),
      ),
    );
    expect(bearerField.obscureText, isTrue);

    // Conversation id breadcrumb selectable + read-only.
    expect(
      find.byKey(const Key('providerForm.swift-infer.conversationId')),
      findsOneWidget,
    );
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
    final addHeader = find.byKey(
      const Key('providerForm.swift-infer.extra.add'),
    );
    await tester.ensureVisible(addHeader);
    await tester.tap(addHeader);
    await tester.pump();
    expect(
      find.byKey(const Key('providerForm.swift-infer.extra.0.key')),
      findsOneWidget,
    );

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
    await tester.tap(
      find.byKey(const Key('providerForm.swift-infer.extra.0.remove')),
    );
    await tester.pump();
    expect((last! as SwiftInferUiConfig).extraHeaders, isEmpty);
  });

  testWidgets('swift-infer subform: sampling knobs push through', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(
      _host(
        onChanged: (c) => last = c,
        initial: SwiftInferUiConfig(
          bearerToken: 'tok',
          endpoint: Uri.parse('http://localhost:8080'),
        ),
      ),
    );
    await tester.pump();

    for (final key in const <String>[
      'providerForm.swift-infer.reasoningEffort',
      'providerForm.swift-infer.maxTokens',
      'providerForm.swift-infer.temperature',
      'providerForm.swift-infer.presencePenalty',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    await tester.enterText(
      find.byKey(const Key('providerForm.swift-infer.maxTokens')),
      '16384',
    );
    await tester.enterText(
      find.byKey(const Key('providerForm.swift-infer.temperature')),
      '0.7',
    );
    await tester.pump();
    final pushed = last! as SwiftInferUiConfig;
    expect(pushed.maxTokens, 16384);
    expect(pushed.temperature, 0.7);
    expect(pushed.presencePenalty, isNull);
    expect(pushed.reasoningEffort, isNull);
  });

  testWidgets('swift-infer subform: picking an effort pushes it', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(
      _host(
        onChanged: (c) => last = c,
        initial: SwiftInferUiConfig(
          bearerToken: 'tok',
          endpoint: Uri.parse('http://localhost:8080'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('providerForm.swift-infer.reasoningEffort')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('medium').last);
    await tester.pumpAndSettle();
    expect(
      (last! as SwiftInferUiConfig).reasoningEffort,
      SwiftInferReasoningEffort.medium,
    );
  });

  testWidgets('switching to anthropic shows obscured api key field', (
    tester,
  ) async {
    ProviderConfig? last;
    await tester.pumpWidget(_host(onChanged: (c) => last = c));
    await tester.pump();

    await tester.tap(find.byKey(const Key('providerForm.providerSelect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('anthropic').last);
    await tester.pumpAndSettle();

    expect(last, isA<AnthropicUiConfig>());
    final keyField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('providerForm.anthropic.apiKey')),
        matching: find.byType(TextField),
      ),
    );
    expect(keyField.obscureText, isTrue);
  });

  testWidgets('proxied initial OpenAI config remains editable', (tester) async {
    ProviderConfig? last;
    await tester.pumpWidget(
      _host(
        onChanged: (c) => last = c,
        initial: OpenAiUiConfig(
          apiKey: 'sk-proxy',
          baseUrlOverride: Uri.parse('https://proxy.example.com/openai'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('providerForm.openai')), findsOneWidget);
    final keyField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('providerForm.openai.apiKey')),
        matching: find.byType(TextField),
      ),
    );
    expect(keyField.obscureText, isTrue);

    final baseUrl = find.byKey(const Key('providerForm.openai.baseUrl'));
    expect(baseUrl, findsOneWidget);
    expect(
      tester.widget<TextFormField>(baseUrl).controller!.text,
      'https://proxy.example.com/openai',
    );

    await tester.enterText(baseUrl, 'https://edited.example.com/v1');
    await tester.pump();

    expect(last, isA<OpenAiUiConfig>());
    expect(
      (last! as OpenAiUiConfig).baseUrlOverride,
      Uri.parse('https://edited.example.com/v1'),
    );
  });

  testWidgets(
    'stale same-provider initial does not revert operator-edited fields',
    (tester) async {
      final probes =
          <
            ({
              String name,
              ProviderConfig initial,
              ProviderConfig stale,
              Key secretKey,
              String editedSecret,
              Key baseUrlKey,
              String editedBaseUrl,
              String headerName,
              String expectedHeader,
            })
          >[
            (
              name: 'swift-infer',
              initial: SwiftInferUiConfig(
                bearerToken: 'initial-token',
                endpoint: Uri.parse('http://initial.example.com/swift'),
              ),
              stale: SwiftInferUiConfig(
                bearerToken: 'stale-token',
                endpoint: Uri.parse('http://stale.example.com/swift'),
              ),
              secretKey: const Key('providerForm.swift-infer.bearer'),
              editedSecret: 'edited-token',
              baseUrlKey: const Key('providerForm.swift-infer.endpoint'),
              editedBaseUrl: 'http://edited.example.com/swift',
              headerName: 'authorization',
              expectedHeader: 'Bearer edited-token',
            ),
            (
              name: 'anthropic',
              initial: AnthropicUiConfig(
                apiKey: 'initial-key',
                baseUrlOverride: Uri.parse(
                  'https://initial.example.com/anthropic',
                ),
              ),
              stale: AnthropicUiConfig(
                apiKey: 'stale-key',
                baseUrlOverride: Uri.parse(
                  'https://stale.example.com/anthropic',
                ),
              ),
              secretKey: const Key('providerForm.anthropic.apiKey'),
              editedSecret: 'edited-key',
              baseUrlKey: const Key('providerForm.anthropic.baseUrl'),
              editedBaseUrl: 'https://edited.example.com/anthropic',
              headerName: 'x-api-key',
              expectedHeader: 'edited-key',
            ),
            (
              name: 'proxied OpenAI',
              initial: OpenAiUiConfig(
                apiKey: 'initial-key',
                baseUrlOverride: Uri.parse(
                  'https://initial.example.com/openai',
                ),
              ),
              stale: OpenAiUiConfig(
                apiKey: 'stale-key',
                baseUrlOverride: Uri.parse('https://stale.example.com/openai'),
              ),
              secretKey: const Key('providerForm.openai.apiKey'),
              editedSecret: 'edited-key',
              baseUrlKey: const Key('providerForm.openai.baseUrl'),
              editedBaseUrl: 'https://edited.example.com/openai',
              headerName: 'authorization',
              expectedHeader: 'Bearer edited-key',
            ),
          ];

      for (final probe in probes) {
        ProviderConfig parentInitial = probe.initial;
        late StateSetter rebuildParent;
        http.Request? captured;
        final ModelCatalog catalog = ModelCatalog(
          client: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode(<String, Object?>{
                'data': <Map<String, Object?>>[
                  <String, Object?>{'id': 'model'},
                ],
              }),
              200,
            );
          }),
        );

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              rebuildParent = setState;
              return _host(
                initial: parentInitial,
                catalog: catalog,
                onChanged: (_) {},
              );
            },
          ),
        );
        await tester.pump();

        await tester.enterText(find.byKey(probe.secretKey), probe.editedSecret);
        await tester.enterText(
          find.byKey(probe.baseUrlKey),
          probe.editedBaseUrl,
        );
        await tester.pump();

        rebuildParent(() => parentInitial = probe.stale);
        await tester.pump();

        final Finder testConnection = find.byKey(
          const Key('providerForm.testConnection'),
        );
        await tester.ensureVisible(testConnection);
        await tester.tap(testConnection);
        await tester.pumpAndSettle();

        expect(captured, isNotNull, reason: probe.name);
        expect(
          captured!.headers[probe.headerName],
          probe.expectedHeader,
          reason: probe.name,
        );
        expect(
          captured!.url,
          Uri.parse('${probe.editedBaseUrl}/v1/models'),
          reason: probe.name,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

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
    await tester.pumpWidget(
      _host(
        onChanged: (_) {},
        initial: SwiftInferUiConfig(
          bearerToken: 'tok',
          endpoint: Uri.parse('http://localhost:8080'),
        ),
        catalog: catalog,
      ),
    );
    await tester.pump();

    final testConnection = find.byKey(const Key('providerForm.testConnection'));
    await tester.ensureVisible(testConnection);
    await tester.tap(testConnection);
    await tester.pumpAndSettle();

    expect(find.textContaining('OK ('), findsOneWidget);
  });
}
