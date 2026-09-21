@Tags(<String>['live'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

const String _bundleIdEnv = 'LEONARD_NATIVE_MACOS_BUNDLE_ID';
const String _serverEnv = 'LEONARD_NATIVE_APPIUM_SERVER';

void main() {
  test(
    'attaches to the running Butane bundle and performs safe Mac actions',
    () async {
      if (!Platform.isMacOS) {
        markTestSkipped('macOS is required for the Appium mac2 live proof');
        return;
      }

      final String? bundleId = Platform.environment[_bundleIdEnv];
      if (bundleId == null || bundleId.isEmpty) {
        markTestSkipped('$_bundleIdEnv is required for the mac2 live proof');
        return;
      }

      final Uri server = Uri.parse(
        Platform.environment[_serverEnv] ?? 'http://127.0.0.1:4723',
      );
      try {
        final http.Response status = await http
            .get(server.resolve('/status'))
            .timeout(const Duration(seconds: 2));
        if (status.statusCode < 200 || status.statusCode >= 300) {
          markTestSkipped(
            'Appium at $server did not answer /status successfully '
            '(HTTP ${status.statusCode})',
          );
          return;
        }
      } on Object catch (error) {
        markTestSkipped('Appium at $server is unavailable: $error');
        return;
      }

      final Mac2Backend backend = Mac2Backend(
        server: server,
        bundleId: bundleId,
      );
      try {
        try {
          await backend.connect();
        } on NativeException catch (error) {
          markTestSkipped(
            'mac2 could not attach; verify Appium 3, the mac2 driver, the '
            'running bundle, and Accessibility permission: ${error.message}',
          );
          return;
        }

        final NativeSnapshot before = await backend.snapshot();
        expect(before.platform, 'darwin');
        expect(before.nodes, isNotEmpty);
        final NativeNode central = before.nodes.firstWhere(
          (NativeNode node) => node.label == 'Central',
        );
        for (final NativeNode node in before.nodes) {
          final Map<String, Object?> record = node.toRecord();
          expect(record.keys.take(3), <String>['id', 'role', 'rect']);
          expect(record, isNot(contains('xpath')));
          expect(record, isNot(contains('resourceId')));
        }

        final NativeTarget? target = await backend.resolve(
          const NativeSelector(label: 'Central'),
          before,
        );
        expect(target, isNotNull);
        await backend.tap(target!);
        await backend.press('return');

        final List<int> rect = central.rect;
        final int centerX = ((rect[0] + rect[2]) / 2).round();
        final int centerY = ((rect[1] + rect[3]) / 2).round();
        final int delta = math.max(1, math.min(8, (rect[2] - rect[0]) ~/ 4));
        await backend.swipe(
          NativeSwipe(
            fromX: math.max(rect[0], centerX - delta),
            fromY: centerY,
            toX: math.min(rect[2], centerX + delta),
            toY: centerY,
            durationMs: 150,
          ),
        );

        final NativeSnapshot after = await backend.snapshot();
        expect(after.platform, 'darwin');
        expect(after.nodes, isNotEmpty);
      } finally {
        await backend.close();
      }
    },
  );
}
