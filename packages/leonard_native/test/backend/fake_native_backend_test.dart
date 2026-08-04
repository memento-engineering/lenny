import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

void main() {
  test(
    'records connect, snapshot, enterText, swipe, and close calls',
    () async {
      final FakeNativeBackend backend = FakeNativeBackend(
        snapshotPayload: _snapshot,
      );
      const NativeTarget target = NativeTarget(
        elementId: 'el-email',
        via: 'a11y-id',
      );
      const NativeSwipe gesture = NativeSwipe(
        fromX: 10,
        fromY: 20,
        toX: 30,
        toY: 40,
        durationMs: 500,
      );

      await backend.connect();
      expect(await backend.snapshot(), same(_snapshot));
      expect(await backend.enterText(target, 'hello'), (
        readback: 'hello',
        masked: false,
      ));
      await backend.swipe(gesture);
      await backend.close();

      expect(backend.calls.map((FakeNativeCall call) => call.name), <String>[
        'connect',
        'snapshot',
        'enterText',
        'swipe',
        'close',
      ]);
      expect(backend.calls[0].detail, isEmpty);
      expect(backend.calls[1].detail, isNull);
      final ({NativeTarget target, String text}) enterTextDetail =
          backend.calls[2].detail! as ({NativeTarget target, String text});
      expect(enterTextDetail.target, same(target));
      expect(enterTextDetail.text, 'hello');
      expect(backend.calls[3].detail, same(gesture));
      expect(backend.calls[4].detail, isNull);
    },
  );

  test('connect records an immutable copy of extra capabilities', () async {
    final FakeNativeBackend backend = FakeNativeBackend();
    final Map<String, Object?> extras = <String, Object?>{
      'appium:autoGrantPermissions': true,
    };

    await backend.connect(extraCapabilities: extras);
    extras['appium:autoGrantPermissions'] = false;

    expect(backend.calls.single.detail, <String, Object?>{
      'appium:autoGrantPermissions': true,
    });
    expect(
      () => (backend.calls.single.detail! as Map<String, Object?>)['other'] = 1,
      throwsUnsupportedError,
    );
  });

  test('pushSnapshot emits on watch and replaces snapshot payload', () async {
    final FakeNativeBackend backend = FakeNativeBackend();
    addTearDown(backend.close);
    final Future<NativeSnapshot> emitted = backend.watch().first;

    backend.pushSnapshot(_snapshot);

    expect(await emitted, same(_snapshot));
    expect(await backend.snapshot(), same(_snapshot));
  });

  test('scripts enterText after recording the call', () async {
    final FakeNativeBackend backend = FakeNativeBackend();
    const NativeTarget target = NativeTarget(elementId: 'E', via: 'xpath');
    backend.enterTextHandler = (NativeTarget actual, String text) async {
      expect(backend.calls.single.name, 'enterText');
      expect(actual, same(target));
      if (text == 'throw') throw NativeException('scripted write failure');
      return (readback: 'scripted:$text', masked: true);
    };

    expect(await backend.enterText(target, 'ok'), (
      readback: 'scripted:ok',
      masked: true,
    ));
    backend.calls.clear();
    await expectLater(
      backend.enterText(target, 'throw'),
      throwsA(isA<NativeException>()),
    );
  });

  test('scripts press after recording the call', () async {
    final FakeNativeBackend backend = FakeNativeBackend();
    backend.pressHandler = (String key) async {
      expect(backend.calls.single.name, 'press');
      if (key == 'throw') throw NativeException('scripted press failure');
    };

    await backend.press('dismiss_overlay');
    backend.calls.clear();
    await expectLater(backend.press('throw'), throwsA(isA<NativeException>()));
  });

  test(
    'built-in resolver honors tier priority and stable target format',
    () async {
      final FakeNativeBackend backend = FakeNativeBackend();
      addTearDown(backend.close);

      final NativeTarget? a11y = await backend.resolve(
        const NativeSelector(
          a11yId: 'login',
          label: 'Email',
          xpath: '//fallback',
          rect: <int>[0, 0, 10, 10],
        ),
        _snapshot,
      );
      expect(a11y?.via, 'a11y-id');
      expect(a11y?.elementId, 'el-login');

      final NativeTarget? label = await backend.resolve(
        const NativeSelector(
          label: 'Email',
          xpath: '//fallback',
          rect: <int>[0, 0, 10, 10],
        ),
        _snapshot,
      );
      expect(label?.via, 'label');
      expect(label?.elementId, 'el-email-id');

      final NativeTarget? anonymousLabel = await backend.resolve(
        const NativeSelector(label: 'Anonymous'),
        _snapshot,
      );
      expect(anonymousLabel?.via, 'label');
      expect(anonymousLabel?.elementId, 'el-(//field)[2]');

      final NativeTarget? xpath = await backend.resolve(
        const NativeSelector(xpath: '//field', rect: <int>[0, 0, 10, 10]),
        _snapshot,
      );
      expect(xpath?.via, 'xpath');
      expect(xpath?.elementId, 'el-//field');

      final NativeTarget? rect = await backend.resolve(
        const NativeSelector(rect: <int>[10, 20, 30, 40]),
        _snapshot,
      );
      expect(rect?.via, 'rect-center');
      expect(rect?.elementId, isNull);
      expect(rect?.point, (x: 20, y: 30));
    },
  );
}

const NativeSnapshot _snapshot = NativeSnapshot(
  platform: 'ios',
  nodes: <NativeNode>[
    NativeNode(
      id: 1,
      role: 'textfield',
      label: 'Email',
      rect: <int>[0, 0, 100, 40],
      a11yId: 'email-id',
      xpath: '//email-fallback',
    ),
    NativeNode(
      id: 2,
      role: 'textfield',
      label: 'Anonymous',
      rect: <int>[0, 50, 100, 90],
      xpath: '(//field)[2]',
    ),
  ],
);
