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
  test('tool manifest snapshot includes schemas and defaults', () async {
    final FakeNativeBackend fake = _fake();
    final NativeExtension ext = NativeExtension(fake);
    final LeonardTool swipe = ext.tools.firstWhere((t) => t.name == 'swipe');

    final ToolResult result = await swipe.call(<String, Object?>{
      'from': <int>[1, 2],
      'to': <int>[3, 4],
    });

    expect(result.ok, isTrue);
    final NativeSwipe gesture =
        fake.calls.singleWhere((c) => c.name == 'swipe').detail! as NativeSwipe;
    expect(
      <Map<String, Object?>>[
        for (final LeonardTool tool in ext.tools)
          <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            'inputSchema': tool.inputSchema.raw,
            'defaults': tool.name == 'swipe'
                ? <String, Object?>{'duration_ms': gesture.durationMs}
                : <String, Object?>{},
          },
      ],
      <Map<String, Object?>>[
        <String, Object?>{
          'name': 'tap',
          'description':
              'Tap a native element. Resolve it by a11y id, label, XPath, or '
              'rect (tried in that order; the winning tier is reported as '
              '`via`).',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'id': <String, Object?>{
                'type': 'string',
                'description': 'a11y identifier (tier 1)',
              },
              'label': <String, Object?>{
                'type': 'string',
                'description': 'visible label (tier 2)',
              },
              'xpath': <String, Object?>{
                'type': 'string',
                'description':
                    "XPath, e.g. //XCUIElementTypeTextField[@name='Email "
                    "address'] (tier 3)",
              },
              'rect': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'integer'},
                'description':
                    '[l,t,r,b]; taps the center (tier 4, last resort)',
              },
            },
            'additionalProperties': false,
          },
          'defaults': <String, Object?>{},
        },
        <String, Object?>{
          'name': 'enter_text',
          'description':
              'Clear and type text into a native field, then dismiss the '
              'keyboard. Returns the element-type-derived `masked` flag and '
              'the `readback` value (a secure field reads back masked bullets, '
              'never plaintext).',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'id': <String, Object?>{
                'type': 'string',
                'description': 'a11y identifier (tier 1)',
              },
              'label': <String, Object?>{
                'type': 'string',
                'description': 'visible label (tier 2)',
              },
              'xpath': <String, Object?>{
                'type': 'string',
                'description':
                    "XPath, e.g. //XCUIElementTypeTextField[@name='Email "
                    "address'] (tier 3)",
              },
              'rect': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'integer'},
                'description':
                    '[l,t,r,b]; taps the center (tier 4, last resort)',
              },
              'text': <String, Object?>{'type': 'string'},
            },
            'required': <String>['text'],
            'additionalProperties': false,
          },
          'defaults': <String, Object?>{},
        },
        <String, Object?>{
          'name': 'press',
          'description':
              'Issue a logical key press. Shared by iOS and Android: '
              'enter/return/done. iOS-only: consent_accept/alert_dismiss '
              '(consent_accept accepts the iOS sign-in consent alert; '
              'alert_dismiss dismisses an iOS system alert, e.g. the Save '
              'Password prompt). Android-only: back. An unrecognized key is a '
              'structured error.',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'key': <String, Object?>{'type': 'string'},
            },
            'required': <String>['key'],
            'additionalProperties': false,
          },
          'defaults': <String, Object?>{},
        },
        <String, Object?>{
          'name': 'swipe',
          'description':
              'Swipe from one point to another (each [x,y] ints). Optional '
              'duration_ms (default 300).',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'from': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'integer'},
                'description': '[x,y] start point',
              },
              'to': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'integer'},
                'description': '[x,y] end point',
              },
              'duration_ms': <String, Object?>{'type': 'integer'},
            },
            'required': <String>['from', 'to'],
            'additionalProperties': false,
          },
          'defaults': <String, Object?>{'duration_ms': 300},
        },
      ],
    );
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

  test(
    'enter_text dismisses, re-resolves, and retries with a fresh target',
    () async {
      final FakeNativeBackend fake = _fake();
      final NativeExtension ext = await _initialized(fake);
      addTearDown(ext.dispose);
      fake.calls.clear();
      var resolveCount = 0;
      var writeCount = 0;
      fake.resolver = (NativeSelector selector, NativeSnapshot? cached) async {
        resolveCount++;
        return NativeTarget(
          elementId: resolveCount == 1 ? 'stale-E' : 'fresh-E',
          via: resolveCount == 1 ? 'stale-via' : 'fresh-via',
        );
      };
      fake.enterTextHandler = (NativeTarget target, String text) async {
        writeCount++;
        if (writeCount == 1) {
          throw NativeException(
            'original obstruction',
            code: NativeException.fieldObscuredCode,
          );
        }
        expect(target.elementId, 'fresh-E');
        return (readback: 'fresh readback', masked: false);
      };
      fake.pressHandler = (String key) async {
        expect(key, 'dismiss_overlay');
      };

      final LeonardTool tool = ext.tools.firstWhere(
        (t) => t.name == 'enter_text',
      );
      final result = await tool.call(<String, Object?>{
        'id': 'Email address',
        'text': 'hello',
      });

      expect(result.ok, isTrue);
      expect((result.value! as Map)['via'], 'fresh-via');
      expect((result.value! as Map)['readback'], 'fresh readback');
      expect(fake.calls.map((FakeNativeCall c) => c.name), <String>[
        'resolve',
        'enterText',
        'press',
        'snapshot',
        'resolve',
        'enterText',
        'snapshot',
      ]);
      final List<String?> writtenIds = fake.calls
          .where((FakeNativeCall c) => c.name == 'enterText')
          .map(
            (FakeNativeCall c) =>
                (c.detail! as ({NativeTarget target, String text}))
                    .target
                    .elementId,
          )
          .toList();
      expect(writtenIds, <String?>['stale-E', 'fresh-E']);
    },
  );

  group('enter_text obstruction recovery failures', () {
    Future<({FakeNativeBackend fake, LeonardTool tool, NativeExtension ext})>
    setup({
      required Future<({String readback, bool masked})> Function(
        NativeTarget target,
        String text,
      )
      write,
      Future<void> Function(String key)? press,
      Future<NativeTarget?> Function(
        NativeSelector selector,
        NativeSnapshot? cached,
      )?
      resolver,
    }) async {
      final FakeNativeBackend fake = _fake();
      final NativeExtension ext = await _initialized(fake);
      fake.calls.clear();
      fake.enterTextHandler = write;
      fake.pressHandler = press;
      if (resolver != null) fake.resolver = resolver;
      return (
        fake: fake,
        tool: ext.tools.firstWhere((t) => t.name == 'enter_text'),
        ext: ext,
      );
    }

    test('non-obstruction failure stays single-attempt', () async {
      final state = await setup(
        write: (NativeTarget target, String text) async =>
            throw NativeException('ordinary failure'),
      );
      addTearDown(state.ext.dispose);
      final result = await state.tool.call(<String, Object?>{
        'id': 'Email address',
        'text': 'hello',
      });
      expect(result.error, 'ordinary failure');
      expect(state.fake.calls.map((c) => c.name), <String>[
        'resolve',
        'enterText',
      ]);
    });

    test('dismiss failure preserves the original obstruction', () async {
      final state = await setup(
        write: (NativeTarget target, String text) async =>
            throw NativeException(
              'original obstruction',
              code: NativeException.fieldObscuredCode,
            ),
        press: (String key) async => throw NativeException('dismiss failed'),
      );
      addTearDown(state.ext.dispose);
      final result = await state.tool.call(<String, Object?>{
        'id': 'Email address',
        'text': 'hello',
      });
      expect(result.error, 'original obstruction');
      expect(state.fake.calls.map((c) => c.name), <String>[
        'resolve',
        'enterText',
        'press',
      ]);
    });

    test('missing fresh target stops after one recovery sequence', () async {
      var resolves = 0;
      final state = await setup(
        write: (NativeTarget target, String text) async =>
            throw NativeException(
              'original obstruction',
              code: NativeException.fieldObscuredCode,
            ),
        press: (String key) async {},
        resolver: (NativeSelector selector, NativeSnapshot? cached) async {
          resolves++;
          return resolves == 1
              ? const NativeTarget(elementId: 'stale-E', via: 'xpath')
              : null;
        },
      );
      addTearDown(state.ext.dispose);
      final result = await state.tool.call(<String, Object?>{
        'id': 'Email address',
        'text': 'hello',
      });
      expect(result.error, 'element disappeared after obstruction dismissal');
      expect(state.fake.calls.map((c) => c.name), <String>[
        'resolve',
        'enterText',
        'press',
        'snapshot',
        'resolve',
      ]);
    });

    test('retry failure is returned without recursive recovery', () async {
      var writes = 0;
      final state = await setup(
        write: (NativeTarget target, String text) async {
          writes++;
          throw NativeException(
            writes == 1 ? 'first obstruction' : 'second obstruction',
            code: NativeException.fieldObscuredCode,
          );
        },
        press: (String key) async {},
      );
      addTearDown(state.ext.dispose);
      final result = await state.tool.call(<String, Object?>{
        'id': 'Email address',
        'text': 'hello',
      });
      expect(result.error, 'second obstruction');
      expect(state.fake.calls.where((c) => c.name == 'press'), hasLength(1));
      expect(
        state.fake.calls.where((c) => c.name == 'enterText'),
        hasLength(2),
      );
    });
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
}
