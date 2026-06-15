import 'package:leonard_flutter/src/errors/error_ring_buffer.dart';
import 'package:leonard_flutter/src/observation/core_fragment.dart';
import 'package:leonard_flutter/src/observation/observation_request.dart';
import 'package:leonard_flutter/src/observation/stability_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

StabilityMetadata _stub() => const StabilityMetadata(
      policy: StabilityPolicy.actionRelative,
      terminatedBy: TerminatedBy.idle,
      durationMs: 16,
      frameworkBusy: <String, Object?>{},
      extensionsBusy: <ExtensionBusy>[],
    );

/// Compute the core fragment values and project them to the legacy map.
Future<Map<String, Object?>> _coreMap({
  required Future<List<Map<String, Object>>> Function() captureSemantics,
  required List<ErrorEntry> Function(int? cursor) errorsSince,
  required StabilityMetadata stability,
  required bool includeScreenshot,
  required Future<String?> Function()? captureScreenshot,
  required int? errorCursor,
  List<String> Function()? routeStackProvider,
}) async {
  final CoreFragmentValues values = await computeCoreFragmentValues(
    captureSemantics: captureSemantics,
    errorsSince: errorsSince,
    stability: stability,
    includeScreenshot: includeScreenshot,
    captureScreenshot: captureScreenshot,
    errorCursor: errorCursor,
    routeStackProvider: routeStackProvider,
  );
  return values.toMap();
}

void main() {
  group('computeCoreFragmentValues', () {
    test('contains semantics, routes, errors, stability', () async {
      final Map<String, Object?> core = await _coreMap(
        captureSemantics: () async => <Map<String, Object>>[
          <String, Object>{'id': 1, 'role': 'button'},
        ],
        errorsSince: (int? c) => const <ErrorEntry>[],
        stability: _stub(),
        includeScreenshot: false,
        captureScreenshot: null,
        errorCursor: null,
        routeStackProvider: () => <String>['/'],
      );
      expect(core.keys, containsAll(<String>[
        'semantics',
        'routes',
        'errors',
        'stability',
      ]));
      expect(core['routes'], <String>['/']);
      expect(
        (core['semantics']! as List<dynamic>).single,
        <String, Object>{'id': 1, 'role': 'button'},
      );
      expect(core.containsKey('screenshot_png_b64'), isFalse);
    });

    test('omits screenshot_png_b64 when includeScreenshot is false', () async {
      bool called = false;
      final Map<String, Object?> core = await _coreMap(
        captureSemantics: () async => const <Map<String, Object>>[],
        errorsSince: (int? c) => const <ErrorEntry>[],
        stability: _stub(),
        includeScreenshot: false,
        captureScreenshot: () async {
          called = true;
          return 'IGNORED';
        },
        errorCursor: null,
        routeStackProvider: () => const <String>[],
      );
      expect(core.containsKey('screenshot_png_b64'), isFalse);
      expect(called, isFalse);
    });

    test('includes screenshot_png_b64 when flag true and capture returns',
        () async {
      final Map<String, Object?> core = await _coreMap(
        captureSemantics: () async => const <Map<String, Object>>[],
        errorsSince: (int? c) => const <ErrorEntry>[],
        stability: _stub(),
        includeScreenshot: true,
        captureScreenshot: () async => 'b64data',
        errorCursor: null,
        routeStackProvider: () => const <String>[],
      );
      expect(core['screenshot_png_b64'], 'b64data');
    });

    test('routes empty list when no Navigator (provider returns [])',
        () async {
      final Map<String, Object?> core = await _coreMap(
        captureSemantics: () async => const <Map<String, Object>>[],
        errorsSince: (int? c) => const <ErrorEntry>[],
        stability: _stub(),
        includeScreenshot: false,
        captureScreenshot: null,
        errorCursor: null,
        routeStackProvider: () => const <String>[],
      );
      expect(core['routes'], <String>[]);
    });

    test('errorsSince forwards the cursor and projects entries to JSON',
        () async {
      int? capturedCursor;
      final Stopwatch clock = Stopwatch()..start();
      final ErrorRingBuffer ring = ErrorRingBuffer(
        capacity: 4,
        sessionClock: clock,
      );
      ring.add('boom', null);
      final Map<String, Object?> core = await _coreMap(
        captureSemantics: () async => const <Map<String, Object>>[],
        errorsSince: (int? c) {
          capturedCursor = c;
          return ring.entriesSince(c ?? 0);
        },
        stability: _stub(),
        includeScreenshot: false,
        captureScreenshot: null,
        errorCursor: 0,
        routeStackProvider: () => const <String>[],
      );
      expect(capturedCursor, 0);
      final List<dynamic> errs = core['errors']! as List<dynamic>;
      expect(errs, hasLength(1));
      expect((errs.first as Map<String, Object?>)['message'], 'boom');
    });
  });
}
