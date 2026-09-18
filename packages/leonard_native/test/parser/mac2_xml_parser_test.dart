import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

File _fixture() {
  for (final String path in <String>[
    'test/fixtures/butane_macos_source.xml',
    'packages/leonard_native/test/fixtures/butane_macos_source.xml',
  ]) {
    final File file = File(path);
    if (file.existsSync()) return file;
  }
  fail(
    'butane_macos_source.xml fixture not found from '
    '${Directory.current.path}',
  );
}

NativeNode _byLabel(List<NativeNode> nodes, String label) =>
    nodes.firstWhere((NativeNode node) => node.label == label);

void main() {
  late Mac2Backend backend;
  late List<NativeNode> nodes;

  setUpAll(() {
    backend = Mac2Backend(bundleId: 'com.nicospencer.butaneHarness');
    nodes = backend.parseSource(_fixture().readAsStringSync());
  });

  tearDownAll(() => backend.close());

  test('keeps controls from the Butane app and layered system alert', () {
    expect(nodes.map((NativeNode node) => node.id), <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    expect(nodes.map((NativeNode node) => node.label), <String?>[
      'Central',
      'Connect',
      'Endpoint',
      null,
      'System alert',
      'Butane would like to use Bluetooth',
      "Don't Allow",
      'Allow',
    ]);
    expect(
      nodes.any(
        (NativeNode node) =>
            node.label == 'Central' && node.a11yId == 'central-title',
      ),
      isTrue,
    );
    expect(
      nodes.any(
        (NativeNode node) =>
            node.label == 'Allow' && node.a11yId == 'permission-allow',
      ),
      isTrue,
    );
  });

  test('emits canonical records and keeps selectors off the wire', () {
    final NativeNode central = _byLabel(nodes, 'Central');
    expect(central.role, 'text');
    expect(central.rect, <int>[284, 164, 404, 192]);
    expect(
      central.xpath,
      "//XCUIElementTypeStaticText[@identifier='central-title']",
    );
    expect(central.toRecord(), <String, Object?>{
      'id': 1,
      'role': 'text',
      'rect': <int>[284, 164, 404, 192],
      'label': 'Central',
      'identifier': 'central-title',
    });
    expect(central.toRecord().keys, <String>[
      'id',
      'role',
      'rect',
      'label',
      'identifier',
    ]);
    expect(central.toRecord(), isNot(contains('xpath')));
    expect(central.toRecord(), isNot(contains('resourceId')));

    final NativeNode endpoint = _byLabel(nodes, 'Endpoint');
    expect(endpoint.role, 'textfield');
    expect(endpoint.toRecord().keys, <String>[
      'id',
      'role',
      'rect',
      'label',
      'identifier',
      'value',
    ]);
    expect(endpoint.value, 'http://127.0.0.1:8080');
  });

  test('maps the complete mac2 role vocabulary', () {
    const String xml = '''
<AppiumAUT>
  <XCUIElementTypeButton identifier="button"/>
  <XCUIElementTypeTextField identifier="field"/>
  <XCUIElementTypeSecureTextField identifier="secure"/>
  <XCUIElementTypeTextView identifier="view"/>
  <XCUIElementTypeLink identifier="link"/>
  <XCUIElementTypeStaticText identifier="text"/>
  <XCUIElementTypeImage/>
  <XCUIElementTypeCheckBox identifier="check"/>
  <XCUIElementTypeSwitch identifier="switch"/>
  <XCUIElementTypeSlider identifier="slider"/>
</AppiumAUT>''';
    expect(
      backend.parseSource(xml).map((NativeNode node) => node.role),
      <String>[
        'button',
        'textfield',
        'textfield',
        'textfield',
        'link',
        'text',
        'image',
        'checkbox',
        'switch',
        'slider',
      ],
    );
  });

  test('uses title fallback and deterministic positional XPath', () {
    const String xml = '''
<AppiumAUT>
  <XCUIElementTypeButton identifier="duplicate" title="First"/>
  <XCUIElementTypeButton identifier="duplicate" title="Second"/>
  <XCUIElementTypeImage/>
  <XCUIElementTypeImage/>
</AppiumAUT>''';
    final List<NativeNode> parsed = backend.parseSource(xml);
    expect(parsed.map((NativeNode node) => node.label), <String?>[
      'First',
      'Second',
      null,
      null,
    ]);
    expect(parsed.map((NativeNode node) => node.xpath), <String?>[
      '(//XCUIElementTypeButton)[1]',
      '(//XCUIElementTypeButton)[2]',
      '(//XCUIElementTypeImage)[1]',
      '(//XCUIElementTypeImage)[2]',
    ]);
  });

  test('quotes identifiers safely in XPath literals', () {
    const String xml = '''
<AppiumAUT>
  <XCUIElementTypeButton identifier="owner's &quot;button&quot;"/>
</AppiumAUT>''';
    expect(
      backend.parseSource(xml).single.xpath,
      r'''//XCUIElementTypeButton[@identifier=concat('owner', "'", 's "button"')]''',
    );
  });
}
