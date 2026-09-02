/// The picker's auto-populate precedence, which decides which model the
/// INNER panel session runs: an explicit `ProviderConfig.defaultModelId`
/// outranks the compile-time [kDefaultSwiftInferModelId], which outranks the
/// first fetched model.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_agent/leonard_agent.dart' show ExtensionManifestEntry;
import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/prompt_panel.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';

const String _kOther = 'qwen3.8-27b-8bit';

ModelCatalog _emptyCatalog() => ModelCatalog(
  client: MockClient(
    (http.Request req) async => http.Response(
      jsonEncode(<String, dynamic>{'data': <Map<String, dynamic>>[]}),
      200,
    ),
  ),
);

SwiftInferUiConfig _config({String? defaultModelId}) => SwiftInferUiConfig(
  bearerToken: 'tok',
  endpoint: Uri.parse('http://localhost:8080'),
  defaultModelId: defaultModelId ?? kDefaultSwiftInferModelId,
);

Widget _host({required List<ResolvedModel> models, ProviderConfig? config}) =>
    MaterialApp(
      home: Scaffold(
        body: PromptPanel(
          modelsState: ModelCatalogState(models: models, config: config),
          extensions: const <ExtensionManifestEntry>[],
          running: false,
          onStart: (_) {},
          onStop: () {},
          onProviderConfigChanged: (_) {},
          onReloadModels: () {},
          catalog: _emptyCatalog(),
        ),
      ),
    );

Future<String> _resolvedReadout(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('prompt.settingsGear')));
  await tester.pumpAndSettle();
  return tester
      .widget<Text>(find.byKey(const Key('prompt.resolvedModel')))
      .data!;
}

void main() {
  testWidgets('the compile-time default wins over a later fetched model', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        models: <ResolvedModel>[
          const ResolvedModel(id: _kOther, label: _kOther),
          ResolvedModel(
            id: kDefaultSwiftInferModelId,
            label: kDefaultSwiftInferModelId,
          ),
        ],
        config: _config(),
      ),
    );
    expect(
      await _resolvedReadout(tester),
      'Resolved model: $kDefaultSwiftInferModelId',
    );
  });

  testWidgets('an explicit config defaultModelId outranks the build define', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        models: <ResolvedModel>[
          ResolvedModel(
            id: kDefaultSwiftInferModelId,
            label: kDefaultSwiftInferModelId,
          ),
          const ResolvedModel(id: _kOther, label: _kOther),
        ],
        config: _config(defaultModelId: _kOther),
      ),
    );
    expect(await _resolvedReadout(tester), 'Resolved model: $_kOther');
  });

  testWidgets('a preferred id absent from the list falls back to the first', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        models: <ResolvedModel>[const ResolvedModel(id: 'mlx', label: 'MLX')],
        config: _config(defaultModelId: _kOther),
      ),
    );
    expect(await _resolvedReadout(tester), 'Resolved model: mlx');
  });

  testWidgets('an empty catalog reports no resolved model', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(models: const <ResolvedModel>[], config: _config()),
    );
    expect(await _resolvedReadout(tester), 'Resolved model: none');
  });
}
