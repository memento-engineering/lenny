/// UNIT: locks the `--platform` wiring the host runner depends on — that
/// `android` selects UiAutomator2, `ios` selects XCUITest, `darwin` selects
/// Mac2, and an unknown platform fails LOUD instead of silently defaulting
/// (which would parse an Android tree with an XCUITest parser and observe
/// nothing). Also locks the lifecycle choice: `app` launches, `appId`
/// attaches, on both mobile platforms alike.
library;

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

void main() {
  test('android + app -> launching UiAutomator2Backend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'android',
      udid: 'emulator-5554',
      app: '/x/app.apk',
      platformVersion: '13',
    );
    expect(b, isA<UiAutomator2Backend>());
    final UiAutomator2Backend android = b as UiAutomator2Backend;
    expect(android.app, '/x/app.apk');
    expect(android.appId, isNull);
    expect(android.platformVersion, '13');
    b.close();
  });

  test('android + appId -> attaching UiAutomator2Backend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'android',
      udid: 'emulator-5554',
      appId: 'com.example.app',
    );
    final UiAutomator2Backend android = b as UiAutomator2Backend;
    expect(android.appId, 'com.example.app');
    expect(android.app, isNull);
    b.close();
  });

  for (final String? version in <String?>[null, '']) {
    test('android accepts ${version == null ? 'null' : 'empty'} version', () {
      final NativeBackend backend = backendForPlatform(
        platform: 'android',
        udid: 'emulator-5554',
        appId: 'com.example.app',
        platformVersion: version,
      );
      expect(backend, isA<UiAutomator2Backend>());
      expect(
        (backend as UiAutomator2Backend).obstructionIds.permissionDialogEntries,
        ObstructionResourceIdPolicy.defaults().permissionDialogEntries,
      );
      backend.close();
    });
  }

  test('ios + app -> launching XcuiTestBackend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'ios',
      udid: 'SIM-UDID',
      app: '/x/Runner.app',
      platformVersion: '26.0',
    );
    final XcuiTestBackend ios = b as XcuiTestBackend;
    expect(ios.app, '/x/Runner.app');
    expect(ios.appId, isNull);
    expect(ios.platformVersion, '26.0');
    b.close();
  });

  test('ios + appId -> attaching XcuiTestBackend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'ios',
      udid: 'SIM-UDID',
      appId: 'engineering.memento.Runner',
    );
    final XcuiTestBackend ios = b as XcuiTestBackend;
    expect(ios.appId, 'engineering.memento.Runner');
    expect(ios.app, isNull);
    b.close();
  });

  test('darwin -> bundle-targeted Mac2Backend', () {
    final Uri server = Uri.parse('http://127.0.0.1:4998');
    final NativeBackend backend = backendForPlatform(
      platform: 'darwin',
      appId: 'com.nicospencer.butaneHarness',
      server: server,
    );
    expect(backend, isA<Mac2Backend>());
    expect((backend as Mac2Backend).bundleId, 'com.nicospencer.butaneHarness');
    expect(backend.server, server);
    backend.close();
  });

  for (final String platform in <String>['ios', 'android']) {
    for (final String? missing in <String?>[null, '']) {
      final String label = missing == null ? 'missing' : 'empty';

      test('$platform rejects $label udid', () {
        expect(
          () => backendForPlatform(
            platform: platform,
            udid: missing,
            app: '/x/app',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.name,
              'name',
              'udid',
            ),
          ),
        );
      });

      test('$platform rejects $label app and appId', () {
        expect(
          () => backendForPlatform(
            platform: platform,
            udid: 'DEVICE',
            app: missing,
            appId: missing,
          ),
          throwsA(
            isA<ArgumentError>()
                .having((ArgumentError error) => error.name, 'name', 'app')
                .having(
                  (ArgumentError error) => error.message.toString(),
                  'message',
                  allOf(contains('app'), contains('appId')),
                ),
          ),
        );
      });
    }

    test('$platform rejects app and appId together', () {
      expect(
        () => backendForPlatform(
          platform: platform,
          udid: 'DEVICE',
          app: '/x/app',
          appId: 'com.example.app',
        ),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError error) => error.name, 'name', 'appId')
              .having(
                (ArgumentError error) => error.message.toString(),
                'message',
                contains('not both'),
              ),
        ),
      );
    });
  }

  for (final String? appId in <String?>[null, '']) {
    test('darwin rejects ${appId == null ? 'missing' : 'empty'} appId', () {
      expect(
        () => backendForPlatform(platform: 'darwin', appId: appId),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'appId',
          ),
        ),
      );
    });
  }

  test('an unknown platform throws ArgumentError (LOUD, no iOS fallback)', () {
    expect(
      () =>
          backendForPlatform(platform: 'windows', udid: 'W', app: '/x/app.exe'),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message.toString(),
          'message',
          allOf(contains('ios'), contains('android'), contains('darwin')),
        ),
      ),
    );
  });

  test('the server override is threaded through', () {
    final NativeBackend b = backendForPlatform(
      platform: 'android',
      udid: 'emulator-5554',
      appId: 'com.example.app',
      platformVersion: '13',
      server: Uri.parse('http://127.0.0.1:4999'),
    );
    expect((b as UiAutomator2Backend).server.port, 4999);
    b.close();
  });
}
