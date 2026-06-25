/// AC3, AC4, AC7 — handshake union (namespaces + de-duped first-seen-order
/// capabilities), native advertised, collision detected at start() (m3).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '_fakes.dart';

void main() {
  group('handshake union (AC3, AC4)', () {
    test('merges namespaces, advertises native, de-dupes capabilities '
        'first-seen', () async {
      // Flutter host: core + router, reports `screenshot`.
      final RecordingVmService flutter = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
          ext('router', <String>['go']),
        ],
        capabilities: const <String>['screenshot'],
      );
      // Native host: native + its four tools; also reports `screenshot`
      // (to prove de-dup keeps it once, first-seen).
      final RecordingVmService native = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('native', <String>['tap', 'enter_text', 'press', 'swipe']),
        ],
        capabilities: const <String>['screenshot'],
      );

      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(flutter), clientOver(native)],
      );
      await session.start('goal', const LeonardConfig());

      final HandshakeResult merged = session.handshake;

      // All three namespaces present, bare tools intact.
      final Map<String, List<String>> byNs = <String, List<String>>{
        for (final ExtensionManifestEntry e in merged.extensions)
          e.namespace: e.tools,
      };
      expect(byNs.keys, containsAll(<String>['core', 'router', 'native']));
      expect(
        byNs['native'],
        equals(<String>['tap', 'enter_text', 'press', 'swipe']),
      );

      // Capabilities: union, de-duped, FIRST-SEEN order (NOT sorted) —
      // `screenshot` appears exactly once.
      expect(merged.capabilities, equals(<String>['screenshot']));

      // Contract version = primary (first) channel's.
      expect(merged.contractVersion, equals('2'));

      // buildExtensionTools emits core.*, router.*, AND native.* descriptors.
      final Map<String, List<ToolDescriptor>> tools = buildExtensionTools(
        requested: <String>{'core', 'router', 'native'},
        handshake: merged.extensions,
      );
      expect(tools.keys, containsAll(<String>['core', 'router', 'native']));
      expect(
        tools['native']!.map((ToolDescriptor t) => t.name),
        containsAll(<String>[
          'native.tap',
          'native.enter_text',
          'native.press',
          'native.swipe',
        ]),
      );
    });

    test(
      'capability de-dup preserves first-seen wire order across hosts',
      () async {
        final RecordingVmService a = RecordingVmService(
          extensions: <Map<String, dynamic>>[
            ext('core', <String>['tap']),
          ],
          capabilities: const <String>['screenshot', 'vision'],
        );
        final RecordingVmService b = RecordingVmService(
          extensions: <Map<String, dynamic>>[
            ext('native', <String>['tap']),
          ],
          capabilities: const <String>['vision', 'audio'],
        );
        final MultiHostSession session = MultiHostSession.forTest(
          <VmServiceClient>[clientOver(a), clientOver(b)],
        );
        await session.start('goal', const LeonardConfig());
        // first-seen order: screenshot, vision (a), then audio (b); vision once.
        expect(
          session.handshake.capabilities,
          equals(<String>['screenshot', 'vision', 'audio']),
        );
      },
    );
  });

  group('namespace collision (AC7)', () {
    test('two hosts both reporting `core` throws at start()', () async {
      final RecordingVmService a = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
      );
      final RecordingVmService b = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
      );
      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(a), clientOver(b)],
      );

      await expectLater(
        session.start('goal', const LeonardConfig()),
        throwsA(
          isA<MultiHostNamespaceCollision>().having(
            (MultiHostNamespaceCollision e) => e.namespace,
            'namespace',
            'core',
          ),
        ),
      );
    });
  });
}
