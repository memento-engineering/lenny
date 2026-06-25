import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart' show Observation;
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

NativeSnapshot _snapshot() => const NativeSnapshot(
  platform: 'ios',
  nodes: <NativeNode>[
    NativeNode(
      id: 1,
      role: 'button',
      label: 'Log in',
      rect: <int>[156, 450, 246, 498],
      a11yId: 'Log in',
    ),
  ],
);

/// Builds a host over a NativeExtension on a fresh fake, and runs [body]. The
/// host initializes the extension itself (via its first prepared entrypoint),
/// seeding the watcher off the fake's snapshot. The fake is returned so the
/// test can inspect recorded calls.
Future<FakeNativeBackend> _withHost(
  Future<void> Function(ExplorationHost host) body,
) async {
  final FakeNativeBackend fake = FakeNativeBackend(
    snapshotPayload: _snapshot(),
  );
  final NativeExtension ext = NativeExtension(fake);
  final ExplorationHost host = ExplorationHost(
    extensions: <LeonardExtension>[ext],
  );
  try {
    await body(host);
  } finally {
    await ext.dispose();
  }
  return fake;
}

void main() {
  group('ExplorationHost(NativeExtension) wire shapes', () {
    test(
      'handshake lists the four native tools + empty capabilities',
      () async {
        await _withHost((host) async {
          final Map<String, dynamic> hs =
              jsonDecode(await host.handshakeJson()) as Map<String, dynamic>;
          expect(hs['bindingType'], 'LeonardHost');
          expect(hs['capabilities'], isEmpty);
          final List<Map<String, dynamic>> exts = (hs['extensions'] as List)
              .cast<Map<String, dynamic>>();
          expect(exts.single['namespace'], 'native');
          expect(exts.single['tools'], <String>[
            'tap',
            'enter_text',
            'press',
            'swipe',
          ]);
        });
      },
    );

    test('observation round-trips with extensions.native present', () async {
      await _withHost((host) async {
        final Map<String, dynamic> env =
            jsonDecode(await host.observationJson()) as Map<String, dynamic>;
        final Map<String, dynamic> value = (env['value'] as Map)
            .cast<String, dynamic>();
        final Observation obs = Observation.fromJson(value);
        expect(obs.extensions.keys, contains('native'));
        expect(jsonEncode(value['extensions']), contains('elements'));
      });
    });

    test('invoke dispatches native.tap and returns {ok:true}', () async {
      await _withHost((host) async {
        // The driver JSON-encodes each arg value on the wire as a string.
        final Map<String, dynamic> env =
            jsonDecode(
                  await host.invokeToolJson('native.tap', <String, String>{
                    'id': jsonEncode('Log in'),
                  }),
                )
                as Map<String, dynamic>;
        expect(env['ok'], true);
        expect((env['value'] as Map)['via'], 'a11y-id');
      });
    });

    test('a consent_accept press is recorded on the backend', () async {
      final FakeNativeBackend fake = await _withHost((host) async {
        final Map<String, dynamic> env =
            jsonDecode(
                  await host.invokeToolJson('native.press', <String, String>{
                    'key': jsonEncode('consent_accept'),
                  }),
                )
                as Map<String, dynamic>;
        expect(env['ok'], true);
      });
      expect(
        fake.calls.any(
          (c) => c.name == 'press' && c.detail == 'consent_accept',
        ),
        isTrue,
      );
    });
  });
}
