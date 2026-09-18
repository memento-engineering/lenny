/// UNIT: locks the `--platform` wiring the host runner depends on — that
/// `android` selects UiAutomator2, `ios` selects XCUITest, `darwin` selects
/// Mac2, and an unknown platform fails LOUD instead of silently defaulting
/// (which would parse an Android tree with an XCUITest parser and observe
/// nothing).
library;

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

void main() {
  test('android -> UiAutomator2Backend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'android',
      udid: 'emulator-5554',
      app: 'com.example.app',
      platformVersion: '13',
    );
    expect(b, isA<UiAutomator2Backend>());
    b.close();
  });

  for (final String? version in <String?>[null, '']) {
    test('android accepts ${version == null ? 'null' : 'empty'} version', () {
      final NativeBackend backend = backendForPlatform(
        platform: 'android',
        udid: 'emulator-5554',
        app: 'com.example.app',
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

  test('ios -> XcuiTestBackend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'ios',
      udid: 'SIM-UDID',
      app: '/x/Runner.app',
    );
    expect(b, isA<XcuiTestBackend>());
    b.close();
  });

  test('darwin -> bundle-targeted Mac2Backend', () {
    final Uri server = Uri.parse('http://127.0.0.1:4998');
    final NativeBackend backend = backendForPlatform(
      platform: 'darwin',
      bundleId: 'com.nicospencer.butaneHarness',
      server: server,
    );
    expect(backend, isA<Mac2Backend>());
    expect((backend as Mac2Backend).bundleId, 'com.nicospencer.butaneHarness');
    expect(backend.server, server);
    backend.close();
  });

  for (final String platform in <String>['ios', 'android']) {
    for (final String target in <String>['udid', 'app']) {
      for (final String? missing in <String?>[null, '']) {
        test('$platform rejects ${missing == null ? 'missing' : 'empty'} '
            '$target', () {
          expect(
            () => backendForPlatform(
              platform: platform,
              udid: target == 'udid' ? missing : 'DEVICE',
              app: target == 'app' ? missing : '/x/app',
            ),
            throwsA(
              isA<ArgumentError>().having(
                (ArgumentError error) => error.name,
                'name',
                target,
              ),
            ),
          );
        });
      }
    }
  }

  for (final String? bundleId in <String?>[null, '']) {
    test(
      'darwin rejects ${bundleId == null ? 'missing' : 'empty'} bundleId',
      () {
        expect(
          () => backendForPlatform(platform: 'darwin', bundleId: bundleId),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.name,
              'name',
              'bundleId',
            ),
          ),
        );
      },
    );
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
      app: 'com.example.app',
      platformVersion: '13',
      server: Uri.parse('http://127.0.0.1:4999'),
    );
    expect((b as UiAutomator2Backend).server.port, 4999);
    b.close();
  });
}
