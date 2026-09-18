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

  group('mac2AttachCapabilities', () {
    test('owns the bundle-targeted attach and teardown lifecycle', () {
      final Map<String, Object?> capabilities = mac2AttachCapabilities(
        bundleId: 'com.nicospencer.butaneHarness',
        extraCapabilities: const <String, Object?>{
          'appium:showServerLogs': true,
        },
      );

      expect(capabilities, <String, Object?>{
        'platformName': 'mac',
        'appium:automationName': 'Mac2',
        'appium:bundleId': 'com.nicospencer.butaneHarness',
        'appium:noReset': true,
        'appium:skipAppKill': true,
        'appium:showServerLogs': true,
      });
      expect(
        () => capabilities['appium:showServerLogs'] = false,
        throwsUnsupportedError,
      );
    });

    for (final String key in <String>[
      'appium:skipAppKill',
      'skipAppKill',
      'appium:appPath',
      'appPath',
    ]) {
      test('rejects attach-critical $key', () {
        expect(
          () => mac2AttachCapabilities(
            bundleId: 'com.nicospencer.butaneHarness',
            extraCapabilities: <String, Object?>{key: false},
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message.toString(),
              'message',
              contains(key),
            ),
          ),
        );
      });
    }

    test('rejects an empty bundle id', () {
      expect(
        () => mac2AttachCapabilities(bundleId: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
