/// What an outer driver actually sees of the panel's icon-only buttons: the
/// Settings gear and the Reload models refresh must each capture as ONE
/// labeled, identified button node. The panel self-drive scenario names both
/// by label, so an unlabeled node is an unreachable step.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_agent/leonard_agent.dart' show ExtensionManifestEntry;
import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/prompt_panel.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

ModelCatalog _emptyCatalog() => ModelCatalog(
  client: MockClient(
    (http.Request req) async => http.Response(
      jsonEncode(<String, dynamic>{'data': <Map<String, dynamic>>[]}),
      200,
    ),
  ),
);

Widget _host() => MaterialApp(
  home: Scaffold(
    body: PromptPanel(
      modelsState: const ModelCatalogState(
        models: <ResolvedModel>[ResolvedModel(id: 'mlx', label: 'MLX')],
      ),
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

Map<String, Object> _byIdentifier(
  List<Map<String, Object>> recs,
  String identifier,
) => recs.singleWhere((Map<String, Object> r) => r['identifier'] == identifier);

void main() {
  testWidgets('the Settings gear captures as one labeled, identified button', (
    WidgetTester tester,
  ) async {
    // Roomy surface: off-viewport nodes are filtered out of the capture.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle h = tester.ensureSemantics();

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = await cap.captureAsync();
    final Map<String, Object> gear = _byIdentifier(recs, 'prompt.settingsGear');
    expect(gear['label'], 'Settings');
    expect(gear['role'], 'button');
    expect(gear['actions'], contains('tap'));
    expect(
      recs.where(
        (Map<String, Object> r) =>
            r['role'] == 'button' && r['label'] == 'Settings',
      ),
      hasLength(1),
    );

    cap.dispose();
    h.dispose();
  });

  testWidgets('the Reload models button captures labeled and identified once '
      'the settings reveal is open', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle h = tester.ensureSemantics();

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    // The reveal is closed at first paint; the driver opens it with the gear.
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    // The settings reveal is a fixed-height scroller. Bring the refresh
    // control into its viewport just as the outer driver does before capture.
    await tester.ensureVisible(find.byKey(const Key('prompt.modelsReload')));
    await tester.pumpAndSettle();

    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = await cap.captureAsync();
    final Map<String, Object> reload = _byIdentifier(
      recs,
      'prompt.modelsReload',
    );
    expect(reload['label'], 'Reload models');
    expect(reload['role'], 'button');
    expect(reload['actions'], contains('tap'));
    expect(
      recs.where(
        (Map<String, Object> r) =>
            r['role'] == 'button' && r['label'] == 'Reload models',
      ),
      hasLength(1),
    );

    cap.dispose();
    h.dispose();
  });
}
