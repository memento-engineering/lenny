/// UNIT (NOT e2e): locks the Android **state projection** — the four
/// UiAutomator2 `/source` attributes the node build maps onto the Flutter
/// state vocabulary, the two Flutter tokens Android must never fake, and the
/// empty-not-null floor for a node that carries none of them.
library;

import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

/// The Flutter state vocabulary, verbatim and IN ORDER, mirrored from
/// `packages/leonard_flutter/lib/src/semantics/semantics_capture.dart:304-314`
/// (`SemanticsCapture._state`). `leonard_native` is pure Dart and cannot
/// import the Flutter package, so the vocabulary is mirrored here; the subset
/// test below is what stops the two channels drifting apart silently.
const List<String> kFlutterStateVocabulary = <String>[
  'checked',
  'on',
  'selected',
  'focused',
  'disabled',
  'obscured',
];

/// Resolve a fixture from either invocation cwd (package root or repo root),
/// mirroring `uiautomator2_backend_test.dart`'s dual-path resolver.
File _fixture(String name) {
  for (final String p in <String>[
    'test/fixtures/$name',
    'packages/leonard_native/test/fixtures/$name',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail('$name fixture not found from ${Directory.current.path}');
}

/// Parse [xml] through the REAL backend, closing the http.Client it opens.
List<NativeNode> _parse(String xml) {
  final UiAutomator2Backend backend = UiAutomator2Backend(
    udid: 'fixture',
    app: 'com.example.app',
    platformVersion: '13',
  );
  final List<NativeNode> nodes = backend.parseSource(xml);
  backend.close();
  return nodes;
}

List<NativeNode> _parseFixture(String name) =>
    _parse(_fixture(name).readAsStringSync());

NativeNode _byResourceIdSuffix(List<NativeNode> nodes, String suffix) =>
    nodes.firstWhere((NativeNode n) => (n.resourceId ?? '').endsWith(suffix));

NativeNode _byLabel(List<NativeNode> nodes, String label) =>
    nodes.firstWhere((NativeNode n) => n.label == label);

/// Every state-bearing shape in one synthetic tree: all four attributes at
/// once (with `selected="true"` to prove it is ignored), a checked Switch (to
/// prove `on` is never inferred from the class), and a bare button.
const String _syntheticXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<hierarchy rotation="0">
  <android.widget.EditText class="android.widget.EditText" resource-id="all_four" text="secret" bounds="[0,0][10,10]" checked="true" focused="true" enabled="false" password="true" selected="true"/>
  <android.widget.Switch class="android.widget.Switch" resource-id="toggle" text="Wi-Fi" bounds="[0,20][10,30]" checked="true" enabled="true" focused="false" password="false" selected="true"/>
  <android.widget.Button class="android.widget.Button" resource-id="plain" text="OK" bounds="[0,40][10,50]"/>
</hierarchy>''';

void main() {
  group('UiAutomator2 state projection', () {
    test('maps exactly the four state-bearing attributes, in Flutter order', () {
      final List<NativeNode> nodes = _parse(_syntheticXml);
      // Flutter's order is checked, on, selected, focused, disabled, obscured;
      // Android emits the subset in exactly that relative order.
      expect(_byResourceIdSuffix(nodes, 'all_four').state, <String>[
        'checked',
        'focused',
        'disabled',
        'obscured',
      ]);
    });

    test(
      'never fakes the two Flutter tokens Android cannot honestly report',
      () {
        final List<NativeNode> nodes = _parse(_syntheticXml);
        // `selected="true"` IS present in the source and MUST be ignored: it is
        // a widget-focus artifact, not Flutter's isSelected semantic.
        for (final NativeNode n in nodes) {
          expect(
            n.state,
            isNot(contains('selected')),
            reason: 'UiAutomator2 selected is not Flutter isSelected',
          );
          expect(
            n.state,
            isNot(contains('on')),
            reason: 'deriving `on` would infer widget kind from class name',
          );
        }
        // A checked Switch is `checked`, never `on` — the exact temptation.
        final NativeNode toggle = _byResourceIdSuffix(nodes, 'toggle');
        expect(toggle.role, 'switch');
        expect(toggle.state, <String>['checked']);
      },
    );

    test('a node with no state-bearing attributes reports an empty list', () {
      final NativeNode plain = _byResourceIdSuffix(
        _parse(_syntheticXml),
        'plain',
      );
      // Empty, NOT null and NOT a list of falses: absent means unknown.
      expect(plain.state, isA<List<String>>());
      expect(plain.state, isEmpty);
      // And the wire record still omits the key, exactly as before this change.
      expect(plain.toRecord().containsKey('state'), isFalse);
    });

    test(
      'the real permission-dialog capture reports enabled, unchecked buttons',
      () {
        final List<NativeNode> nodes = _parseFixture(
          'android_permission_dialog_source.xml',
        );
        // enabled="true" checked="false" focused="false" password="false"
        // -> nothing to say, so nothing is said.
        expect(_byLabel(nodes, 'Allow').state, isEmpty);
        expect(_byLabel(nodes, "Don't allow").state, isEmpty);
        expect(
          _byLabel(nodes, 'Allow').toRecord().containsKey('state'),
          isFalse,
        );
      },
    );

    test('a password EditText reports obscured', () {
      final List<NativeNode> nodes = _parseFixture('auth0_android_source.xml');
      final NativeNode pw = _byLabel(nodes, 'Password');
      expect(pw.role, 'textfield');
      expect(pw.state, <String>['obscured']);
      // Non-empty state IS wired — that is the parity NativeNode.state promises.
      expect(pw.toRecord()['state'], <String>['obscured']);
      // Its sibling, password="false", says nothing.
      expect(_byLabel(nodes, 'Email address').state, isEmpty);
    });

    test(
      'a checked accuracy radio reports checked and its sibling does not',
      () {
        final List<NativeNode> nodes = _parseFixture(
          'android_location_permission_source.xml',
        );
        expect(
          _byResourceIdSuffix(
            nodes,
            'permission_location_accuracy_radio_fine',
          ).state,
          <String>['checked'],
        );
        expect(
          _byResourceIdSuffix(
            nodes,
            'permission_location_accuracy_radio_coarse',
          ).state,
          isEmpty,
        );
      },
    );

    test('actions stays empty on Android', () {
      // A DIFFERENT contract — what you may DO, not what IS. Out of scope here
      // and filed separately; this test pins the boundary.
      for (final String name in <String>[
        'android_permission_dialog_source.xml',
        'auth0_android_source.xml',
        'android_location_permission_source.xml',
      ]) {
        for (final NativeNode n in _parseFixture(name)) {
          expect(n.actions, isEmpty, reason: '$name node ${n.id}');
        }
      }
    });

    test('every token emitted across every checked-in fixture is in the '
        'Flutter vocabulary', () {
      final Set<String> emitted = <String>{};
      for (final String name in <String>[
        'android_permission_dialog_source.xml',
        'android_location_permission_source.xml',
        'auth0_android_source.xml',
        'auth0_android_source_sheet_up.xml',
        'flutter_android_semantics_source.xml',
      ]) {
        for (final NativeNode n in _parseFixture(name)) {
          emitted.addAll(n.state);
        }
      }
      for (final NativeNode n in _parse(_syntheticXml)) {
        emitted.addAll(n.state);
      }
      // Subset, so the two channels cannot drift apart silently.
      expect(emitted.difference(kFlutterStateVocabulary.toSet()), isEmpty);
      // And the four Android CAN report are all exercised above.
      expect(emitted, containsAll(<String>['checked', 'disabled', 'obscured']));
    });
  });
}
