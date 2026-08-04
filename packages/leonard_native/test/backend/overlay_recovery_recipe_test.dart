/// UNIT: compiles and exercises the EXACT overlay-recovery recipe published in
/// the README and in the dartdoc on [NativeException.fieldObscuredCode].
///
/// This exists because that recipe is the migration path handed to every
/// backend-direct consumer after 0.2.2's note misfired and told them to delete
/// working code. A published snippet that does not compile — or that drifts from
/// the real API — is worse than none, so it is pinned here rather than trusted
/// to review.
library;

import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

/// The published recipe, structurally verbatim.
Future<({String readback, bool masked})> writeWithOverlayRecovery(
  NativeBackend backend,
  NativeTarget target,
  NativeSelector selector,
  NativeSnapshot? cached,
  String text,
) async {
  ({String readback, bool masked}) result;
  try {
    result = await backend.enterText(target, text);
  } on NativeException catch (e) {
    if (e.code != NativeException.fieldObscuredCode) rethrow;
    await backend.press('dismiss_overlay');
    final NativeTarget? fresh = await backend.resolve(selector, cached);
    if (fresh == null) {
      throw NativeException('element gone after obstruction dismissal');
    }
    result = await backend.enterText(fresh, text);
  }
  return result;
}

void main() {
  test(
    'the recipe recovers when the first write reports fieldObscured',
    () async {
      final _ObscuredOnceBackend backend = _ObscuredOnceBackend();
      final ({String readback, bool masked}) r = await writeWithOverlayRecovery(
        backend,
        const NativeTarget(elementId: 'STALE', via: 'xpath'),
        const NativeSelector(a11yId: 'Email'),
        null,
        'user@example.com',
      );

      expect(r.readback, 'user@example.com');
      // The ORDER is the contract: dismiss, then re-resolve, then retry. The
      // retry must use the FRESH handle — reusing the stale one is the mistake
      // that looks identical to the overlay never clearing.
      expect(backend.trace, <String>[
        'enterText:STALE',
        'press:dismiss_overlay',
        'resolve',
        'enterText:FRESH',
      ]);
    },
  );

  test('a non-obscured failure propagates without dismissing', () async {
    final _AlwaysFailsBackend backend = _AlwaysFailsBackend();
    await expectLater(
      writeWithOverlayRecovery(
        backend,
        const NativeTarget(elementId: 'E', via: 'xpath'),
        const NativeSelector(a11yId: 'Email'),
        null,
        'x',
      ),
      throwsA(isA<NativeException>()),
    );
    expect(
      backend.trace,
      isNot(contains('press:dismiss_overlay')),
      reason:
          'only fieldObscuredCode may trigger a dismissal — a bare back '
          'with no overlay present navigates a Custom Tab away',
    );
  });
}

class _ObscuredOnceBackend extends FakeNativeBackend {
  final List<String> trace = <String>[];
  bool _thrown = false;

  @override
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  ) async {
    trace.add('enterText:${target.elementId}');
    if (!_thrown) {
      _thrown = true;
      throw NativeException(
        'field is obscured',
        code: NativeException.fieldObscuredCode,
      );
    }
    return (readback: text, masked: false);
  }

  @override
  Future<void> press(String key) async => trace.add('press:$key');

  @override
  Future<NativeTarget?> resolve(
    NativeSelector selector,
    NativeSnapshot? cached,
  ) async {
    trace.add('resolve');
    return const NativeTarget(elementId: 'FRESH', via: 'a11y-id');
  }
}

class _AlwaysFailsBackend extends FakeNativeBackend {
  final List<String> trace = <String>[];

  @override
  Future<({String readback, bool masked})> enterText(
    NativeTarget target,
    String text,
  ) async {
    trace.add('enterText:${target.elementId}');
    throw NativeException(
      'stale element reference: gone',
      code: 'stale element reference',
    );
  }

  @override
  Future<void> press(String key) async => trace.add('press:$key');
}
