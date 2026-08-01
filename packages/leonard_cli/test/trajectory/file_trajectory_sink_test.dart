import 'dart:io';

import 'package:leonard_cli/src/file_trajectory_sink.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileTrajectorySink', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('leonard_cli_sink_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('writeLine appends and flushes', () async {
      final path = p.join(tmp.path, 'a.jsonl');
      final sink = await FileTrajectorySink.open(path);
      await sink.writeLine('{"a":1}');
      await sink.writeLine('{"a":2}');
      await sink.flush();
      await sink.close();
      expect(await File(path).readAsLines(), <String>['{"a":1}', '{"a":2}']);
    });

    test('close once is safe and idempotent', () async {
      final path = p.join(tmp.path, 'b.jsonl');
      final sink = await FileTrajectorySink.open(path);
      await sink.close();
      // Second close must be a silent no-op.
      await sink.close();
    });

    test('defaultOutputPath shape', () {
      final path = FileTrajectorySink.defaultOutputPath(
        now: DateTime.utc(2026, 5, 7, 14, 15, 3),
      );
      expect(path, p.join('trajectories', '20260507T141503Z.jsonl'));
    });
  });
}
