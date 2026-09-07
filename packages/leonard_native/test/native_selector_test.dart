// package:xml marks XPath support experimental; this test accepts that API.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

void main() {
  final XmlDocument document = XmlDocument.parse(
    File(
      'test/fixtures/flutter_android_semantics_source.xml',
    ).readAsStringSync(),
  );

  test('flutterIdentifier targets only the clickable-ancestor xpath tier', () {
    final NativeSelector selector = NativeSelector.flutterIdentifier('allow');
    expect(selector.resourceId, isNull);
    expect(selector.a11yId, isNull);
    expect(selector.label, isNull);
    expect(selector.rect, isNull);
    expect(
      selector.xpath,
      '//*[@resource-id=\'allow\']'
      '/ancestor-or-self::*[@clickable="true"][1]',
    );
  });

  test('flutterIdentifier encodes every XPath quote shape', () {
    expect(
      NativeSelector.flutterIdentifier("owner's").xpath,
      '//*[@resource-id="owner\'s"]'
      '/ancestor-or-self::*[@clickable="true"][1]',
    );
    expect(
      NativeSelector.flutterIdentifier('say "allow"').xpath,
      '//*[@resource-id=\'say "allow"\']'
      '/ancestor-or-self::*[@clickable="true"][1]',
    );
    expect(
      NativeSelector.flutterIdentifier('owner\'s "allow"').xpath,
      '//*[@resource-id=concat(\'owner\', "\'", \'s "allow"\')]'
      '/ancestor-or-self::*[@clickable="true"][1]',
    );
  });

  test('flutterIdentifier xpath selects the clickable Button from fixture', () {
    final List<XmlNode> results = document
        .xpath(NativeSelector.flutterIdentifier('allow').xpath!)
        .toList(growable: false);

    expect(results, hasLength(1));
    final XmlElement element = results.single as XmlElement;
    expect(element.name.local, 'android.widget.Button');
    expect(element.getAttribute('class'), 'android.widget.Button');
    expect(element.getAttribute('clickable'), 'true');
    expect(element.getAttribute('resource-id'), isNull);
  });

  test('flutterIdentifier xpath selects nothing for an absent identifier', () {
    final List<XmlNode> results = document
        .xpath(NativeSelector.flutterIdentifier('missing-from-fixture').xpath!)
        .toList(growable: false);

    expect(results, isEmpty);
  });
}
