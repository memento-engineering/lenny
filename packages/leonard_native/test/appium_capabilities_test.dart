import 'package:leonard_native/src/appium_capabilities.dart';
import 'package:test/test.dart';

void main() {
  group('mergeAppiumCapabilities', () {
    test('reports multiple denied keys in sorted comma-joined order', () {
      expect(
        () => mergeAppiumCapabilities(
          defaults: const <String, Object?>{'platformName': 'Android'},
          extraCapabilities: const <String, Object?>{
            'noReset': false,
            'appium:app': '/tmp/Runner.app',
            'appActivity': '.MainActivity',
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            'attach-critical Appium capabilities cannot be overridden: '
                'appActivity, appium:app, noReset',
          ),
        ),
      );
    });

    test('passes through safe unprefixed and prefixed spellings', () {
      expect(
        mergeAppiumCapabilities(
          defaults: const <String, Object?>{
            'platformName': 'Android',
            'appium:newCommandTimeout': 0,
          },
          extraCapabilities: const <String, Object?>{
            'newCommandTimeout': 120,
            'appium:newCommandTimeout': 180,
          },
        ),
        const <String, Object?>{
          'platformName': 'Android',
          'appium:newCommandTimeout': 180,
          'newCommandTimeout': 120,
        },
      );
    });
  });
}
