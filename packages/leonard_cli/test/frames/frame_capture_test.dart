import 'dart:convert';
import 'dart:io';

import 'package:leonard_cli/src/file_trajectory_sink.dart';
import 'package:leonard_cli/src/frame_capture_sink.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'forwards the trajectory unchanged and captures qualifying turns',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-frame-capture-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final String decoratedPath = p.join(temp.path, 'decorated.jsonl');
      final String undecoratedPath = p.join(temp.path, 'undecorated.jsonl');
      final String framesDirectory = p.join(temp.path, 'decorated.frames');
      final List<int> pngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      final List<String> lines = <String>[
        '{"type":"header","schema_version":2}',
        '{"type":"turn","index":6,"observation":{}}',
        jsonEncode(<String, Object?>{
          'type': 'turn',
          'index': 7,
          'observation': <String, Object?>{
            'screenshot_png_b64': base64Encode(pngBytes),
          },
        }),
        '{"type":"footer","outcome":"done"}',
      ];

      final FileTrajectorySink decoratedDelegate =
          await FileTrajectorySink.open(decoratedPath);
      final FrameCaptureSink decorated = FrameCaptureSink(
        delegate: decoratedDelegate,
        framesDirectory: framesDirectory,
      );
      final FileTrajectorySink undecorated = await FileTrajectorySink.open(
        undecoratedPath,
      );
      for (final String line in lines) {
        await decorated.writeLine(line);
        await undecorated.writeLine(line);
      }
      await decorated.flush();
      await undecorated.flush();
      await decorated.close();
      await decorated.close();
      await undecorated.close();

      expect(
        await File(decoratedPath).readAsBytes(),
        await File(undecoratedPath).readAsBytes(),
      );
      final String framePath = p.join(framesDirectory, 'turn-0007.png');
      expect(await File(framePath).readAsBytes(), pngBytes);
      expect(decorated.capturedFramePaths, <String>[framePath]);
      expect(
        () => decorated.capturedFramePaths.add('another.png'),
        throwsUnsupportedError,
      );
      expect(
        await Directory(
          framesDirectory,
        ).list().map((entity) => p.basename(entity.path)).toList(),
        <String>['turn-0007.png'],
      );
    },
  );

  test('forwards malformed records without capturing them', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'leonard-frame-malformed-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final String trajectoryPath = p.join(temp.path, 'run.jsonl');
    final FrameCaptureSink sink = FrameCaptureSink(
      delegate: await FileTrajectorySink.open(trajectoryPath),
      framesDirectory: p.join(temp.path, 'run.frames'),
    );

    await sink.writeLine('not json');
    await sink.writeLine('{"type":"turn","index":"7"}');
    await sink.close();

    expect(
      await File(trajectoryPath).readAsString(),
      'not json\n{"type":"turn","index":"7"}\n',
    );
    expect(sink.capturedFramePaths, isEmpty);
  });

  test('forwards a turn before surfacing invalid base64', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'leonard-frame-invalid-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final String trajectoryPath = p.join(temp.path, 'run.jsonl');
    final FrameCaptureSink sink = FrameCaptureSink(
      delegate: await FileTrajectorySink.open(trajectoryPath),
      framesDirectory: p.join(temp.path, 'run.frames'),
    );
    const String line =
        '{"type":"turn","index":7,"observation":{"screenshot_png_b64":"!"}}';

    await expectLater(sink.writeLine(line), throwsFormatException);
    await sink.close();

    expect(await File(trajectoryPath).readAsString(), '$line\n');
    expect(sink.capturedFramePaths, isEmpty);
  });
}
