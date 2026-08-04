import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

void main() {
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
}
