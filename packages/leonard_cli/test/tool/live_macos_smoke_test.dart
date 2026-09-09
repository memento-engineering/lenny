import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/live_macos_smoke.dart';

void main() {
  group('isValidVmServiceUri', () {
    test('accepts authority-bearing ws and wss URIs', () {
      expect(
        isValidVmServiceUri(Uri.parse('ws://127.0.0.1:8181/service')),
        isTrue,
      );
      expect(
        isValidVmServiceUri(Uri.parse('wss://vm.example.test/service')),
        isTrue,
      );
    });

    test('rejects null, HTTP, and authority-less websocket URIs', () {
      expect(isValidVmServiceUri(null), isFalse);
      expect(
        isValidVmServiceUri(Uri.parse('http://127.0.0.1:8181/service')),
        isFalse,
      );
      expect(isValidVmServiceUri(Uri.parse('ws:service')), isFalse);
    });
  });

  group('containsExactLabel', () {
    test(
      'finds a direct label and labels nested through map and list values',
      () {
        expect(
          containsExactLabel(<String, Object>{
            'label': 'Debounced search',
          }, 'Debounced search'),
          isTrue,
        );
        expect(
          containsExactLabel(<String, Object>{
            'children': <Object>[
              <String, Object>{'label': 'Other'},
              <String, Object>{
                'child': <String, Object>{'label': 'Debounced search'},
              },
            ],
          }, 'Debounced search'),
          isTrue,
        );
      },
    );

    test('rejects partial labels and matching values under another key', () {
      expect(
        containsExactLabel(<String, Object>{
          'label': 'Debounced search field',
        }, 'Debounced search'),
        isFalse,
      );
      expect(
        containsExactLabel(<String, Object>{
          'description': 'Debounced search',
        }, 'Debounced search'),
        isFalse,
      );
    });
  });

  group('validatePngSignature', () {
    const List<int> signature = <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ];

    test('accepts the full signature with trailing payload', () {
      expect(
        () => validatePngSignature(<int>[...signature, 1, 2]),
        returnsNormally,
      );
    });

    test('rejects short and mismatched signatures', () {
      expect(() => validatePngSignature(<int>[0x89, 0x50]), throwsStateError);
      expect(
        () => validatePngSignature(<int>[...signature]..[7] = 0xff),
        throwsStateError,
      );
    });
  });

  group('JSON guards', () {
    test('requireMap accepts string-keyed maps', () {
      expect(
        requireMap(<String, Object>{'ok': true}, 'result'),
        <String, Object>{'ok': true},
      );
    });

    test('requireMap rejects scalars and non-string keys', () {
      expect(() => requireMap('not a map', 'result'), throwsStateError);
      expect(
        () => requireMap(<Object, Object>{1: 'value'}, 'result'),
        throwsStateError,
      );
    });

    test('requireNumber accepts integers and doubles', () {
      expect(requireNumber(12, 'width'), 12);
      expect(requireNumber(12.5, 'width'), 12.5);
    });

    test('requireNumber rejects numeric strings and null', () {
      expect(() => requireNumber('12', 'width'), throwsStateError);
      expect(() => requireNumber(null, 'width'), throwsStateError);
    });
  });

  group('parseLiveMacosSmokeConfiguration', () {
    final String cliWorkspace = p.normalize(p.absolute('cli-workspace'));
    final String environmentWorkspace = p.normalize(
      p.absolute('environment-workspace'),
    );
    final String sourceWorkspace = p.normalize(p.absolute('source-workspace'));

    const List<
      ({
        List<String> arguments,
        Map<String, String> environment,
        String expectedWorkspaceSource,
      })
    >
    precedenceCases =
        <
          ({
            List<String> arguments,
            Map<String, String> environment,
            String expectedWorkspaceSource,
          })
        >[
          (
            arguments: <String>['--target-workspace', 'cli-workspace'],
            environment: <String, String>{
              'LEONARD_LIVE_SMOKE_TARGET_WORKSPACE': 'environment-workspace',
            },
            expectedWorkspaceSource: 'cli',
          ),
          (
            arguments: <String>[],
            environment: <String, String>{
              'LEONARD_LIVE_SMOKE_TARGET_WORKSPACE': 'environment-workspace',
            },
            expectedWorkspaceSource: 'environment',
          ),
          (
            arguments: <String>[],
            environment: <String, String>{},
            expectedWorkspaceSource: 'source',
          ),
          (
            arguments: <String>['--target-workspace', '   '],
            environment: <String, String>{
              'LEONARD_LIVE_SMOKE_TARGET_WORKSPACE': 'environment-workspace',
            },
            expectedWorkspaceSource: 'environment',
          ),
          (
            arguments: <String>['--target-workspace', '   '],
            environment: <String, String>{
              'LEONARD_LIVE_SMOKE_TARGET_WORKSPACE': '   ',
            },
            expectedWorkspaceSource: 'source',
          ),
        ];

    for (final row in precedenceCases) {
      test('uses ${row.expectedWorkspaceSource} workspace', () {
        final LiveMacosSmokeConfiguration configuration =
            parseLiveMacosSmokeConfiguration(
              row.arguments,
              environment: row.environment,
              sourceWorkspace: sourceWorkspace,
            );
        final String expectedWorkspace = switch (row.expectedWorkspaceSource) {
          'cli' => cliWorkspace,
          'environment' => environmentWorkspace,
          'source' => sourceWorkspace,
          _ => throw StateError(
            'unexpected workspace source ${row.expectedWorkspaceSource}',
          ),
        };

        expect(configuration.sourceWorkspace, sourceWorkspace);
        expect(configuration.targetWorkspace, expectedWorkspace);
        expect(configuration.target, p.join('lib', 'main.dart'));
      });
    }

    test('accepts a target override', () {
      final LiveMacosSmokeConfiguration configuration =
          parseLiveMacosSmokeConfiguration(
            <String>['--target', p.join('tool', 'smoke_main.dart')],
            environment: const <String, String>{},
            sourceWorkspace: sourceWorkspace,
          );

      expect(configuration.target, p.join('tool', 'smoke_main.dart'));
    });

    test('rejects unexpected positional arguments', () {
      expect(
        () => parseLiveMacosSmokeConfiguration(
          <String>['unexpected'],
          environment: const <String, String>{},
          sourceWorkspace: sourceWorkspace,
        ),
        throwsFormatException,
      );
    });
  });
}
