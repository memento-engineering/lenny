/// UNIT: locks the `--platform` wiring the host runner depends on — that
/// `android` selects the UiAutomator2 impl, `ios` selects the XCUITest impl,
/// and an unknown platform fails LOUD instead of silently defaulting to iOS
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

  test('android requires a platform version', () {
    expect(
      () => backendForPlatform(
        platform: 'android',
        udid: 'emulator-5554',
        app: 'com.example.app',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('ios -> XcuiTestBackend', () {
    final NativeBackend b = backendForPlatform(
      platform: 'ios',
      udid: 'SIM-UDID',
      app: '/x/Runner.app',
    );
    expect(b, isA<XcuiTestBackend>());
    b.close();
  });

  test('an unknown platform throws ArgumentError (LOUD, no iOS fallback)', () {
    expect(
      () =>
          backendForPlatform(platform: 'windows', udid: 'W', app: '/x/app.exe'),
      throwsA(isA<ArgumentError>()),
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
