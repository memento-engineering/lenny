import 'package:exploration_devtools/src/dtd_trajectory_sink.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFs {
  final Map<String, String> files = {};

  Future<String?> read(Uri uri) async => files[uri.toString()];

  Future<void> write(Uri uri, String contents) async {
    files[uri.toString()] = contents;
  }
}

void main() {
  final uri = Uri.parse('file:///t.jsonl');

  test('writeLine flushes per call and appends', () async {
    final fs = _FakeFs()..files[uri.toString()] = '{"a":1}\n';
    final sink = DtdTrajectorySink(uri: uri, read: fs.read, write: fs.write);

    await sink.writeLine('{"a":2}');
    expect(fs.files[uri.toString()], '{"a":1}\n{"a":2}\n');

    await sink.writeLine('{"a":3}');
    expect(fs.files[uri.toString()], '{"a":1}\n{"a":2}\n{"a":3}\n');
  });

  test('writeLine starts a fresh file when read returns null', () async {
    final fs = _FakeFs();
    final sink = DtdTrajectorySink(uri: uri, read: fs.read, write: fs.write);

    await sink.writeLine('{"a":1}');
    expect(fs.files[uri.toString()], '{"a":1}\n');
  });

  test('close is idempotent and rejects further writes', () async {
    final fs = _FakeFs();
    final sink = DtdTrajectorySink(uri: uri, read: fs.read, write: fs.write);

    await sink.close();
    await sink.close();

    expect(() => sink.writeLine('x'), throwsA(isA<StateError>()));
  });
}
