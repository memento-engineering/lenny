import 'dart:convert';

import 'package:diagnostic_fixture/main.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _diagnosticsExt =
    'ext.exploration.core.diagnostics_warnings';

/// Integration test for the cx6.10 connect-time diagnostic. Drives the
/// fixture's [HitScreen] / [CleanScreen] through the production
/// [ExplorationBinding] and asserts the wire payload returned by
/// `ext.exploration.core.diagnostics_warnings`.
///
/// All assertions run as plain `test()`. The production binding extends
/// [WidgetsFlutterBinding] and intentionally rejects co-installation
/// alongside `AutomatedTestWidgetsFlutterBinding` (PRD §6.5), so we
/// cannot use the `WidgetTester` driver. Instead we build each fixture
/// screen through a private [BuildOwner] / [RootWidget.attach] pair —
/// the same plumbing `runApp` uses internally — and feed the resulting
/// [Element] tree into the diagnostic via the test-only root-provider
/// seam on the binding.
void main() {
  late ExplorationBinding binding;

  setUpAll(() {
    binding = ExplorationBinding.ensureInitialized(plugins: const [])!;
  });

  setUp(() {
    binding.debugSetDiagnosticsRootProviderForTesting(null);
  });

  Future<List<Map<String, Object?>>> callDiagnostics() async {
    final String resp =
        await binding.invokeServiceExtension(_diagnosticsExt, const {});
    final Map<String, Object?> body =
        jsonDecode(resp) as Map<String, Object?>;
    expect(body['ok'], isTrue);
    return (body['results']! as List<Object?>)
        .cast<Map<String, Object?>>();
  }

  /// Inflate [w] under a fresh [BuildOwner] and return the root element.
  /// The auditor only walks `visitChildren`, so we never need to lay out
  /// or paint the tree — `RootWidget.attach` is enough. We wrap in
  /// `MediaQuery` + `Directionality` directly rather than going through
  /// `MaterialApp`, because `MaterialApp` resolves its `MediaQuery` from
  /// the surrounding `View` (which only exists when a real renderer
  /// pipeline is attached).
  Element buildOffline(Widget screen) {
    final BuildOwner owner = BuildOwner(focusManager: FocusManager());
    final RootWidget root = RootWidget(
      debugShortDescription: '[diagnostic_fixture_test_root]',
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ScaffoldMessenger(child: screen),
        ),
      ),
    );
    return root.attach(owner);
  }

  test('hit screen produces one GestureDetector warning', () async {
    final Element root = buildOffline(const HitScreen());
    binding.debugSetDiagnosticsRootProviderForTesting(() => root);

    final List<Map<String, Object?>> results = await callDiagnostics();
    final Iterable<Map<String, Object?>> hits = results.where(
        (Map<String, Object?> r) => r['widget_type'] == 'GestureDetector');
    expect(hits, hasLength(1),
        reason: 'HitScreen has exactly one bare GestureDetector.');
    expect(hits.first['suggested_fix_pointer'], kPluginGuideFixPointer);
  });

  test('clean screen produces zero GestureDetector warnings', () async {
    final Element root = buildOffline(const CleanScreen());
    binding.debugSetDiagnosticsRootProviderForTesting(() => root);

    final List<Map<String, Object?>> results = await callDiagnostics();
    final Iterable<Map<String, Object?>> hits = results.where(
        (Map<String, Object?> r) => r['widget_type'] == 'GestureDetector');
    expect(hits, isEmpty,
        reason:
            'CleanScreen wraps its GestureDetector in a label-bearing '
            'Semantics ancestor; the auditor must skip it.');
  });
}
