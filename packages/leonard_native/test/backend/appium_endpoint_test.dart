import 'package:leonard_native/src/appium_endpoint.dart';
import 'package:test/test.dart';

void main() {
  group('appiumEndpoint', () {
    const Map<String, String> expected = <String, String>{
      'http://h:4723': 'http://h:4723/session',
      'http://h:4723/': 'http://h:4723/session',
      'http://h:4723/wd/hub': 'http://h:4723/wd/hub/session',
      'http://h:4723/wd/hub/': 'http://h:4723/wd/hub/session',
    };

    for (final MapEntry<String, String> row in expected.entries) {
      test('${row.key} + /session -> ${row.value}', () {
        expect(
          appiumEndpoint(Uri.parse(row.key), '/session').toString(),
          row.value,
        );
      });
    }

    test('keeps the base path under a nested endpoint', () {
      expect(
        appiumEndpoint(
          Uri.parse('https://grid.example:4444/wd/hub'),
          '/session/s1/element/e2/value',
        ).toString(),
        'https://grid.example:4444/wd/hub/session/s1/element/e2/value',
      );
    });

    test('matches Uri.resolve for a server with no base path', () {
      for (final String server in <String>['http://h:4723', 'http://h:4723/']) {
        final Uri base = Uri.parse(server);
        for (final String path in <String>['/session', '/session/s/source']) {
          expect(appiumEndpoint(base, path), base.resolve(path));
        }
      }
    });
  });
}
