import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'gauntlet_live_harness.dart';

class FakeOracleReader implements GauntletOracleReader {
  FakeOracleReader(this.value);

  final Map<String, Object?> value;
  bool called = false;
  Uri? seenUri;

  @override
  Future<Map<String, Object?>> read(Uri uri) async {
    called = true;
    seenUri = uri;
    return value;
  }
}

Map<String, Object?> oracle(
  String id, {
  Map<String, Object?> expected = const <String, Object?>{},
  bool reached = false,
}) => <String, Object?>{
  'active': true,
  'oracle': <String, Object?>{
    'scenario_id': id,
    'expected': expected,
    'goal_reached': reached,
  },
};

void main() {
  final Uri uri = Uri.parse('ws://127.0.0.1:1/token/ws');
  const LeonardDrive drive = LeonardDrive('/repo/leonard_drive.dart', '/repo');

  test('adapter invokes leonard_drive', () async {
    late List<String> seen;
    final LeonardDrive fake = LeonardDrive(
      '/drive.dart',
      '/app',
      run:
          (
            String command,
            List<String> args, {
            String? workingDirectory,
          }) async {
            expect(command, Platform.resolvedExecutable);
            expect(workingDirectory, '/app');
            seen = args;
            return ProcessResult(1, 0, '{"observation":{}}', '');
          },
    );

    expect(await fake.observe(uri), contains('observation'));
    expect(seen, <String>[
      'run',
      '/drive.dart',
      'observe',
      '--vm-uri',
      uri.toString(),
    ]);
  });

  for (final String id in GauntletLiveHarness.interactionIds) {
    test('$id passes only when goal_reached is true', () async {
      for (final bool reached in <bool>[true, false]) {
        final FakeOracleReader reader = FakeOracleReader(
          oracle(id, reached: reached),
        );
        final Future<void> result = GauntletLiveHarness(drive, reader: reader)
            .run(
              uri: uri,
              route: '/g/$id',
              goal: 'complete $id',
              driver:
                  (GauntletDriveRequest request, LeonardDrive adapter) async {
                    expect(request.route, '/g/$id');
                    expect(request.goal, 'complete $id');
                    expect(request.uri, uri);
                    expect(adapter, same(drive));
                    expect(reader.called, isFalse);
                    return <String, Object?>{};
                  },
            );

        if (reached) {
          await result;
          expect(reader.seenUri, uri);
        } else {
          await expectLater(result, throwsStateError);
        }
      }
    });
  }

  test('answer verdict normalizes and requires every entry', () async {
    final FakeOracleReader reader = FakeOracleReader(
      oracle(
        'vision/semantics-lie',
        expected: <String, Object?>{'error_tile': 'Tile 3', 'error_index': 2},
      ),
    );
    final GauntletLiveHarness harness = GauntletLiveHarness(
      drive,
      reader: reader,
    );

    await harness.run(
      uri: uri,
      route: '/g/vision/semantics-lie',
      goal: 'report error_tile and error_index',
      driver: (_, _) async => <String, Object?>{
        'error_tile': ' tile 3 ',
        'error_index': 2.0,
      },
    );
    await expectLater(
      harness.run(
        uri: uri,
        route: '/g/vision/semantics-lie',
        goal: 'report error_tile and error_index',
        driver: (_, _) async => <String, Object?>{'error_tile': 'Tile 3'},
      ),
      throwsStateError,
    );
  });

  test('answer verdict requires the goal to name every expected key', () async {
    final Future<void> result =
        GauntletLiveHarness(
          drive,
          reader: FakeOracleReader(
            oracle(
              'vision/chart-read',
              expected: <String, Object?>{'answer': 'Q3'},
            ),
          ),
        ).run(
          uri: uri,
          route: '/g/vision/chart-read',
          goal: 'read the chart',
          driver: (_, _) async => <String, Object?>{'answer': 'Q3'},
        );

    await expectLater(result, throwsStateError);
  });

  test('answer verdict rejects a mismatched reported value', () async {
    final Future<void> result =
        GauntletLiveHarness(
          drive,
          reader: FakeOracleReader(
            oracle(
              'vision/count-spatial',
              expected: <String, Object?>{'count': 8},
            ),
          ),
        ).run(
          uri: uri,
          route: '/g/vision/count-spatial',
          goal: 'report count',
          driver: (_, _) async => <String, Object?>{'count': 9},
        );

    await expectLater(result, throwsStateError);
  });

  test('bad oracle states fail naming the requested scenario', () async {
    for (final Map<String, Object?> value in <Map<String, Object?>>[
      <String, Object?>{'active': false},
      <String, Object?>{'active': true, 'oracle': 'bad'},
      oracle('vision/chart-read', expected: <String, Object?>{'answer': 'Q3'}),
      oracle('vision/ocr-price'),
    ]) {
      final Future<void> result =
          GauntletLiveHarness(drive, reader: FakeOracleReader(value)).run(
            uri: uri,
            route: '/g/vision/ocr-price',
            goal: 'report price',
            driver: (_, _) async => <String, Object?>{'price': r'$42.99'},
          );

      await expectLater(
        result,
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message.toString(),
            'message',
            contains('vision/ocr-price'),
          ),
        ),
      );
    }
  });

  test('rejects routes outside the gauntlet', () async {
    await expectLater(
      GauntletLiveHarness(
        drive,
        reader: FakeOracleReader(<String, Object?>{}),
      ).run(
        uri: uri,
        route: '/gauntlet',
        goal: 'choose a scenario',
        driver: (_, _) async => <String, Object?>{},
      ),
      throwsArgumentError,
    );
  });
}
