/// UNIT (NOT e2e): exercises `AppiumBackend._parseSource` against a checked-in
/// XCUITest `/source` fixture — no Appium server, no device. Asserts the
/// m2-spec §5.3 worked example: `{x,y,w,h}` -> `[l,t,r,b]` rect conversion,
/// the role vocab, labels, a11yIds, dense document-order ids, and the
/// named-vs-synthesized-positional xpath synthesis.
library;

import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

/// Resolve the fixture from either invocation cwd (package root or repo root),
/// mirroring the tmux e2e's dual-path resolver.
File _fixture() {
  for (final String p in <String>[
    'test/fixtures/auth0_source.xml',
    'packages/leonard_native/test/fixtures/auth0_source.xml',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail('auth0_source.xml fixture not found from cwd ${Directory.current.path}');
}

NativeNode _byLabel(List<NativeNode> nodes, String label) =>
    nodes.firstWhere((NativeNode n) => n.label == label);

void main() {
  late List<NativeNode> nodes;

  setUpAll(() {
    final AppiumBackend backend = AppiumBackend(
      platform: 'ios',
      udid: 'fixture',
      app: '/dev/null',
    );
    nodes = backend.parseSource(_fixture().readAsStringSync());
    // Free the http.Client the constructor opened.
    backend.close();
  });

  test('flattens the a11y tree to the real controls in document order', () {
    // The structural Application/Window/Other scaffolding is dropped; the kept
    // nodes are the real controls, in document order with dense 1-based ids.
    expect(nodes.map((NativeNode n) => n.role).toList(), <String>[
      'button', // Log in
      'text', // opening Auth0…
      'text', // form (named container)
      'image', // anonymous form image #1
      'textfield', // Email address
      'textfield', // Password (SecureTextField -> textfield)
      'switch', // Show password
      'image', // anonymous form image #2
      'link', // Reset password
      'button', // Continue
    ]);
    // Dense, 1-based, document-order ids.
    expect(nodes.map((NativeNode n) => n.id).toList(), <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
  });

  test(
    'Log in button — worked example (id, role, rect, label, a11yId, xpath)',
    () {
      final NativeNode logIn = nodes.first;
      expect(logIn.id, 1);
      expect(logIn.role, 'button');
      expect(logIn.label, 'Log in');
      expect(logIn.a11yId, 'Log in');
      expect(logIn.rect, <int>[156, 450, 246, 498]);
      expect(logIn.xpath, "//XCUIElementTypeButton[@name='Log in']");
      // No value/state/actions/scroll on the button -> omitted from the record.
      expect(logIn.toRecord(), <String, Object?>{
        'id': 1,
        'role': 'button',
        'rect': <int>[156, 450, 246, 498],
        'label': 'Log in',
      });
    },
  );

  test('Email TextField — rect + named xpath, value omitted before typing', () {
    final NativeNode email = _byLabel(nodes, 'Email address');
    expect(email.role, 'textfield');
    expect(email.label, 'Email address');
    expect(email.a11yId, 'Email address');
    expect(email.rect, <int>[40, 376, 362, 428]);
    expect(email.xpath, "//XCUIElementTypeTextField[@name='Email address']");
    expect(email.value, isNull); // empty before typing -> omitted
    expect(email.toRecord().containsKey('value'), isFalse);
  });

  test(
    'Password SecureTextField — textfield role + secure-field named xpath',
    () {
      final NativeNode pw = _byLabel(nodes, 'Password');
      expect(pw.role, 'textfield'); // SecureTextField maps to textfield
      expect(pw.label, 'Password');
      expect(pw.a11yId, 'Password');
      expect(pw.rect, <int>[41, 441, 317, 493]);
      expect(pw.xpath, "//XCUIElementTypeSecureTextField[@name='Password']");
    },
  );

  test('anonymous nodes get deterministic positional xpath synthesis', () {
    // Two anonymous Images (no name/label/value) survive on their non-text
    // role; each gets `(//XCUIElementTypeImage)[n]` by document-order index
    // among kept nodes of that type.
    final List<NativeNode> images = nodes
        .where((NativeNode n) => n.role == 'image')
        .toList();
    expect(images, hasLength(2));
    expect(images[0].a11yId, isNull);
    expect(images[0].xpath, '(//XCUIElementTypeImage)[1]');
    expect(images[1].xpath, '(//XCUIElementTypeImage)[2]');
  });

  test(
    'named-but-non-unique falls through to positional (uniqueness gate)',
    () {
      // Every named node in the fixture is unique per type, so every named node
      // gets a `[@name=…]` xpath (not positional). Assert the two buttons are
      // both named (unique among buttons): Log in + Continue.
      final List<NativeNode> buttons = nodes
          .where((NativeNode n) => n.role == 'button')
          .toList();
      expect(buttons.map((NativeNode n) => n.xpath).toList(), <String>[
        "//XCUIElementTypeButton[@name='Log in']",
        "//XCUIElementTypeButton[@name='Continue']",
      ]);
    },
  );

  test('named-but-DUPLICATE names fall through to positional xpath', () {
    // Two same-type, same-name buttons: the uniqueness gate must push BOTH to
    // positional `(//Type)[n]`, while a uniquely-named sibling stays named.
    // (Closes the _xpathFor false-branch the all-unique fixture never exercises.)
    const String xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<AppiumAUT>
  <XCUIElementTypeApplication name="App">
    <XCUIElementTypeButton name="OK" label="OK" x="0" y="0" width="10" height="10"/>
    <XCUIElementTypeButton name="OK" label="OK" x="0" y="20" width="10" height="10"/>
    <XCUIElementTypeButton name="Cancel" label="Cancel" x="0" y="40" width="10" height="10"/>
  </XCUIElementTypeApplication>
</AppiumAUT>''';
    final AppiumBackend backend = AppiumBackend(
      platform: 'ios',
      udid: 'fixture',
      app: '/dev/null',
    );
    final List<NativeNode> parsed = backend.parseSource(xml);
    backend.close();

    final List<NativeNode> buttons = parsed
        .where((NativeNode n) => n.role == 'button')
        .toList();
    expect(buttons, hasLength(3));
    // Duplicate-named -> positional, by document-order index among buttons.
    expect(buttons[0].xpath, '(//XCUIElementTypeButton)[1]');
    expect(buttons[1].xpath, '(//XCUIElementTypeButton)[2]');
    // Uniquely-named sibling -> stays named.
    expect(buttons[2].xpath, "//XCUIElementTypeButton[@name='Cancel']");
  });
}
