import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

/// A populated snapshot: a named Log in button, a named Email field, and an
/// ANONYMOUS field (no a11yId) carrying a synthesized positional xpath — the
/// load-bearing case for label -> positional-xpath resolution.
NativeSnapshot _populatedSnapshot() => const NativeSnapshot(
  platform: 'ios',
  nodes: <NativeNode>[
    NativeNode(
      id: 1,
      role: 'button',
      label: 'Log in',
      rect: <int>[156, 450, 246, 498],
      a11yId: 'Log in',
      xpath: "//XCUIElementTypeButton[@name='Log in']",
    ),
    NativeNode(
      id: 2,
      role: 'textfield',
      label: 'Email address',
      rect: <int>[40, 376, 362, 428],
      a11yId: 'Email address',
      xpath: "//XCUIElementTypeTextField[@name='Email address']",
    ),
    // Anonymous field: no a11yId, only a synthesized positional xpath.
    NativeNode(
      id: 3,
      role: 'textfield',
      label: 'Anonymous',
      rect: <int>[40, 500, 362, 552],
      xpath: '(//XCUIElementTypeTextField)[2]',
    ),
  ],
);

FakeNativeBackend _fake() =>
    FakeNativeBackend(snapshotPayload: _populatedSnapshot());

Map<String, Object?> _fragment(NativeExtension ext) {
  final PerceptionOwner owner = PerceptionOwner();
  final root = owner.mountRoot(ext.buildPerception());
  final Map<String, Object?> data = serializePerceptionFragment(root);
  owner.unmountRoot();
  return data;
}

Future<NativeExtension> _initialized(FakeNativeBackend fake) async {
  final NativeExtension ext = NativeExtension(fake);
  await ext.initialize(ExtensionContext(namespace: 'native'));
  return ext;
}

void main() {
  test('exposes bare-token contract tools (registry adds the namespace)', () {
    final NativeExtension ext = NativeExtension(_fake());
    expect(ext.namespace, 'native');
    expect(ext.tools.map((t) => t.name), <String>[
      'tap',
      'enter_text',
      'press',
      'swipe',
    ]);
  });

  test('idle before initialize; stateful perception after', () async {
    final NativeExtension ext = NativeExtension(_fake());
    expect(ext.isPerceptionIdle(), isTrue);

    await ext.initialize(ExtensionContext(namespace: 'native'));
    addTearDown(ext.dispose);

    expect(ext.isPerceptionIdle(), isFalse);
  });

  test(
    'fragment carries the canonical record schema (value + omit-empty)',
    () async {
      final NativeExtension ext = await _initialized(_fake());
      addTearDown(ext.dispose);

      final Map<String, Object?> data = _fragment(ext);
      expect(data['platform'], 'ios');
      expect(data['node_count'], 3);
      final List<Object?> elements = data['elements']! as List<Object?>;
      expect(elements, hasLength(3));

      final Map<String, Object?> button = (elements.first! as Map)
          .cast<String, Object?>();
      // id/role/rect always present; label present; identifier present (the
      // a11yId surfaced on the wire); value/state/actions/scroll omitted (empty).
      expect(button.keys.toList(), <String>[
        'id',
        'role',
        'rect',
        'label',
        'identifier',
      ]);
      expect(button['id'], 1);
      expect(button['role'], 'button');
      expect(button['rect'], <int>[156, 450, 246, 498]);
      expect(button['label'], 'Log in');
      expect(button['identifier'], 'Log in');
      expect(button.containsKey('value'), isFalse);
      expect(button.containsKey('state'), isFalse);
    },
  );

  test('fragment emits value when a node has one', () async {
    final FakeNativeBackend fake = FakeNativeBackend(
      snapshotPayload: const NativeSnapshot(
        platform: 'ios',
        nodes: <NativeNode>[
          NativeNode(
            id: 1,
            role: 'textfield',
            label: 'Email address',
            value: 'nonce@example.com',
            rect: <int>[40, 376, 362, 428],
          ),
        ],
      ),
    );
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    final List<Object?> elements = _fragment(ext)['elements']! as List<Object?>;
    final Map<String, Object?> field = (elements.single! as Map)
        .cast<String, Object?>();
    expect(field['value'], 'nonce@example.com');
    // Canonical key order: value sits between label and (absent) state.
    expect(field.keys.toList(), <String>[
      'id',
      'role',
      'rect',
      'label',
      'value',
    ]);
  });

  test('selector chain resolves each tier with the right `via`', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    final LeonardTool tap = ext.tools.firstWhere((t) => t.name == 'tap');

    // tier 1: a11y-id
    final res1 = await tap.call(<String, Object?>{'id': 'Log in'});
    expect(res1.ok, isTrue);
    expect((res1.value! as Map)['via'], 'a11y-id');

    // tier 3: xpath
    final res3 = await tap.call(<String, Object?>{
      'xpath': "//XCUIElementTypeTextField[@name='Email address']",
    });
    expect(res3.ok, isTrue);
    expect((res3.value! as Map)['via'], 'xpath');

    // tier 4: rect-center
    final res4 = await tap.call(<String, Object?>{
      'rect': <int>[40, 376, 362, 428],
    });
    expect(res4.ok, isTrue);
    expect((res4.value! as Map)['via'], 'rect-center');

    // The recorded targets show the resolved point for rect-center.
    final FakeNativeCall rectResolve = fake.calls.lastWhere(
      (c) =>
          c.name == 'resolve' &&
          (c.detail as NativeTarget?)?.via == 'rect-center',
    );
    final NativeTarget t = rectResolve.detail! as NativeTarget;
    expect(t.point, (x: 201, y: 402));
  });

  test('label tier resolves an anonymous node via a synthesized positional '
      'xpath', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    final LeonardTool tap = ext.tools.firstWhere((t) => t.name == 'tap');
    final res = await tap.call(<String, Object?>{'label': 'Anonymous'});
    expect(res.ok, isTrue);
    expect((res.value! as Map)['via'], 'label');

    final NativeTarget t =
        fake.calls.lastWhere((c) => c.name == 'tap').detail! as NativeTarget;
    expect(t.via, 'label');
    // Anonymous node (no a11yId) -> resolved through its positional xpath.
    expect(t.elementId, 'el-(//XCUIElementTypeTextField)[2]');
  });

  test('enter_text reports element-type-derived masked readback', () async {
    // Normal field: echoes typed text, masked:false.
    final FakeNativeBackend normal = _fake();
    final NativeExtension extN = await _initialized(normal);
    addTearDown(extN.dispose);
    final LeonardTool etN = extN.tools.firstWhere(
      (t) => t.name == 'enter_text',
    );
    final resN = await etN.call(<String, Object?>{
      'id': 'Email address',
      'text': 'nonce@example.com',
    });
    expect(resN.ok, isTrue);
    expect((resN.value! as Map)['readback'], 'nonce@example.com');
    expect((resN.value! as Map)['masked'], isFalse);

    // Secure field: masked bullets, masked:true, ≠ plaintext.
    final FakeNativeBackend secure = _fake()..secureFieldValue = 'hunter2';
    final NativeExtension extS = await _initialized(secure);
    addTearDown(extS.dispose);
    final LeonardTool etS = extS.tools.firstWhere(
      (t) => t.name == 'enter_text',
    );
    final resS = await etS.call(<String, Object?>{
      'id': 'Password',
      'text': 'hunter2',
    });
    expect(resS.ok, isTrue);
    final Map<String, Object?> secVal = (resS.value! as Map)
        .cast<String, Object?>();
    expect(secVal['masked'], isTrue);
    expect(secVal['readback'], isNotEmpty);
    expect(secVal['readback'], isNot('hunter2'));
  });

  test('refresh-after-act reflects the post-tap snapshot; '
      'refreshNow is a no-op after dispose', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);

    // After a tap, the fake's snapshot payload changes; refreshNow should
    // pull it so the next observation reflects the change.
    fake.snapshotPayload = const NativeSnapshot(
      platform: 'ios',
      nodes: <NativeNode>[
        NativeNode(
          id: 9,
          role: 'text',
          label: 'Tapped!',
          rect: <int>[0, 0, 1, 1],
        ),
      ],
    );
    final LeonardTool tap = ext.tools.firstWhere((t) => t.name == 'tap');
    await tap.call(<String, Object?>{'id': 'Log in'});

    final List<Object?> elements = _fragment(ext)['elements']! as List<Object?>;
    expect((elements.single! as Map)['label'], 'Tapped!');

    // Dispose, then refreshNow must NOT touch the backend or change _live.
    await ext.dispose();
    final int snapshotCallsBefore = fake.calls
        .where((c) => c.name == 'snapshot')
        .length;
    await ext.refreshNow();
    final int snapshotCallsAfter = fake.calls
        .where((c) => c.name == 'snapshot')
        .length;
    expect(snapshotCallsAfter, snapshotCallsBefore);
  });

  test('watch() resilience: a stream error does not crash the host and keeps '
      'the last-good snapshot', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    expect(ext.isPerceptionIdle(), isFalse);

    // Push a transient error; the extension must survive and keep last-good.
    fake.pushError(StateError('transient /source poll failure'));
    await Future<void>.delayed(Duration.zero);

    expect(ext.isPerceptionIdle(), isFalse);
    final List<Object?> elements = _fragment(ext)['elements']! as List<Object?>;
    expect(elements, hasLength(3));
  });

  test('structured errors, never throws', () async {
    final NativeExtension ext = await _initialized(_fake());
    addTearDown(ext.dispose);

    // enter_text without text.
    final LeonardTool et = ext.tools.firstWhere((t) => t.name == 'enter_text');
    final r1 = await et.call(<String, Object?>{'id': 'Email address'});
    expect(r1.ok, isFalse);
    expect(r1.error, isNotNull);

    // press without key.
    final LeonardTool press = ext.tools.firstWhere((t) => t.name == 'press');
    final r2 = await press.call(const <String, Object?>{});
    expect(r2.ok, isFalse);
    expect(r2.error, isNotNull);

    // press with an unknown key -> backend NativeException caught into ok:false.
    final r3 = await press.call(<String, Object?>{'key': 'bogus'});
    expect(r3.ok, isFalse);
    expect(r3.error, contains('unknown press key'));

    // swipe with a malformed array.
    final LeonardTool swipe = ext.tools.firstWhere((t) => t.name == 'swipe');
    final r4 = await swipe.call(<String, Object?>{
      'from': <int>[1],
      'to': <int>[2, 3],
    });
    expect(r4.ok, isFalse);
    expect(r4.error, isNotNull);

    // tap with an unresolvable selector.
    final LeonardTool tap = ext.tools.firstWhere((t) => t.name == 'tap');
    final r5 = await tap.call(const <String, Object?>{});
    expect(r5.ok, isFalse);
    expect(r5.error, isNotNull);
  });

  test('consent_accept press reaches the backend', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    final LeonardTool press = ext.tools.firstWhere((t) => t.name == 'press');
    final res = await press.call(<String, Object?>{'key': 'consent_accept'});
    expect(res.ok, isTrue);
    expect(
      fake.calls.any((c) => c.name == 'press' && c.detail == 'consent_accept'),
      isTrue,
    );
  });

  // AC2 (m5): `native.press` exposes `alert_dismiss` end to end — the tool
  // forwards the key to backend.press and returns ToolResult(ok:true,
  // value:{'key':'alert_dismiss'}) on success; the description mentions it.
  test('alert_dismiss press forwards to the backend (ok + key echo)', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = await _initialized(fake);
    addTearDown(ext.dispose);

    final LeonardTool press = ext.tools.firstWhere((t) => t.name == 'press');
    final res = await press.call(<String, Object?>{'key': 'alert_dismiss'});
    expect(res.ok, isTrue);
    expect((res.value! as Map)['key'], 'alert_dismiss');
    expect(
      fake.calls.any((c) => c.name == 'press' && c.detail == 'alert_dismiss'),
      isTrue,
    );
  });

  test('press tool description mentions alert_dismiss', () {
    final NativeExtension ext = NativeExtension(_fake());
    final LeonardTool press = ext.tools.firstWhere((t) => t.name == 'press');
    expect(press.description, contains('alert_dismiss'));
  });
}
