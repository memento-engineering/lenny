import 'dart:io';

import 'package:leonard_cli/src/image_golden_comparator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String fixturesDirectory = p.join('test', 'image_goldens');
  String fixture(String name) => p.join(fixturesDirectory, name);

  group('ImageGoldenComparator', () {
    final ImageGoldenComparator comparator = ImageGoldenComparator(
      channelTolerance: 8,
      maxDiffRatio: 0.25,
    );

    test('passes identical pixels', () async {
      final ImageGoldenComparison comparison = await comparator.compareFrame(
        capturedPath: fixture('reference.png'),
        goldenPath: fixture('reference.png'),
      );

      expect(comparison.passed, isTrue);
      expect(comparison.differingPixels, 0);
      expect(comparison.totalPixels, 4);
      expect(comparison.diffRatio, 0.0);
    });

    test('accepts channel deltas exactly equal to tolerance', () async {
      final ImageGoldenComparison comparison = await comparator.compareFrame(
        capturedPath: fixture('within_tolerance.png'),
        goldenPath: fixture('reference.png'),
      );

      expect(comparison.passed, isTrue);
      expect(comparison.differingPixels, 0);
    });

    test('fails only when the differing-pixel ratio exceeds maximum', () async {
      final ImageGoldenComparison comparison = await comparator.compareFrame(
        capturedPath: fixture('beyond_ratio.png'),
        goldenPath: fixture('reference.png'),
      );

      expect(comparison.passed, isFalse);
      expect(
        comparison.failureReason,
        ImageGoldenFailureReason.pixelDifference,
      );
      expect(comparison.differingPixels, 2);
      expect(comparison.totalPixels, 4);
      expect(comparison.diffRatio, 0.5);

      final ImageGoldenComparison boundary =
          await ImageGoldenComparator(
            channelTolerance: 8,
            maxDiffRatio: 0.5,
          ).compareFrame(
            capturedPath: fixture('beyond_ratio.png'),
            goldenPath: fixture('reference.png'),
          );
      expect(boundary.passed, isTrue);
    });

    test('fails dimensions without visiting pixels', () async {
      final ImageGoldenComparison comparison = await comparator.compareFrame(
        capturedPath: fixture('different_dimensions.png'),
        goldenPath: fixture('reference.png'),
      );

      expect(comparison.passed, isFalse);
      expect(
        comparison.failureReason,
        ImageGoldenFailureReason.dimensionMismatch,
      );
      expect(comparison.capturedWidth, 1);
      expect(comparison.capturedHeight, 2);
      expect(comparison.goldenWidth, 2);
      expect(comparison.goldenHeight, 2);
      expect(comparison.differingPixels, isNull);
      expect(comparison.totalPixels, isNull);
      expect(comparison.diffRatio, isNull);
    });

    test(
      'accumulates missing and undecodable goldens in input order',
      () async {
        final Directory temp = await Directory.systemTemp.createTemp(
          'leonard-golden-failures-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final Directory frames = await Directory(
          p.join(temp.path, 'frames'),
        ).create();
        final Directory goldens = await Directory(
          p.join(temp.path, 'image_goldens'),
        ).create();
        final String missingPath = p.join(frames.path, 'missing.png');
        final String invalidPath = p.join(frames.path, 'invalid.png');
        await File(fixture('reference.png')).copy(missingPath);
        await File(fixture('reference.png')).copy(invalidPath);
        await File(
          p.join(goldens.path, 'invalid.png'),
        ).writeAsString('not png');

        final ImageGoldenReport report = await comparator.compareFrames(
          framePaths: <String>[missingPath, invalidPath],
          goldensDirectory: goldens.path,
        );

        expect(report.exitCode, 1);
        expect(
          report.comparisons.map((comparison) => comparison.failureReason),
          <ImageGoldenFailureReason>[
            ImageGoldenFailureReason.missingFile,
            ImageGoldenFailureReason.decodeFailure,
          ],
        );
        final String failures = report.renderFailures();
        expect(failures, contains(missingPath));
        expect(failures, contains(invalidPath));
        expect(
          failures.indexOf(missingPath),
          lessThan(failures.indexOf(invalidPath)),
        );
      },
    );
  });

  group('finishImageGoldenRun', () {
    test('returns zero and emits nothing when all frames pass', () async {
      final StringBuffer output = StringBuffer();
      final StringBuffer error = StringBuffer();

      final int exitCode = await finishImageGoldenRun(
        framePaths: <String>[fixture('reference.png')],
        goldensDirectory: fixturesDirectory,
        channelTolerance: 8,
        maxDiffRatio: 0.0,
        updateGoldens: false,
        output: output,
        error: error,
      );

      expect(exitCode, 0);
      expect(output.toString(), isEmpty);
      expect(error.toString(), isEmpty);
    });

    test('returns one and renders every failing captured path', () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-golden-report-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final Directory frames = await Directory(
        p.join(temp.path, 'frames'),
      ).create();
      final Directory goldens = await Directory(
        p.join(temp.path, 'image_goldens'),
      ).create();
      final String pixelsPath = p.join(frames.path, 'pixels.png');
      final String missingPath = p.join(frames.path, 'missing.png');
      await File(fixture('beyond_ratio.png')).copy(pixelsPath);
      await File(fixture('reference.png')).copy(missingPath);
      await File(
        fixture('reference.png'),
      ).copy(p.join(goldens.path, 'pixels.png'));
      final StringBuffer output = StringBuffer();
      final StringBuffer error = StringBuffer();

      final int exitCode = await finishImageGoldenRun(
        framePaths: <String>[pixelsPath, missingPath],
        goldensDirectory: goldens.path,
        channelTolerance: 8,
        maxDiffRatio: 0.25,
        updateGoldens: false,
        output: output,
        error: error,
      );

      expect(exitCode, 1);
      expect(output.toString(), isEmpty);
      expect(error.toString(), contains(pixelsPath));
      expect(error.toString(), contains(missingPath));
    });

    test('update creates and overwrites baselines without decoding', () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'leonard-golden-update-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final Directory frames = await Directory(
        p.join(temp.path, 'frames'),
      ).create();
      final String framePath = p.join(frames.path, 'turn-0001.png');
      final String goldensDirectory = p.join(temp.path, 'image_goldens');
      final String goldenPath = p.join(goldensDirectory, 'turn-0001.png');
      await File(framePath).writeAsBytes(<int>[1, 2, 3]);

      expect(
        await updateImageGoldens(
          framePaths: <String>[framePath],
          goldensDirectory: goldensDirectory,
        ),
        <String>[goldenPath],
      );
      expect(await File(goldenPath).readAsBytes(), <int>[1, 2, 3]);

      await File(framePath).writeAsBytes(<int>[4, 5]);
      final StringBuffer output = StringBuffer();
      final StringBuffer error = StringBuffer();
      final int exitCode = await finishImageGoldenRun(
        framePaths: <String>[framePath],
        goldensDirectory: goldensDirectory,
        channelTolerance: 8,
        maxDiffRatio: 0.0,
        updateGoldens: true,
        output: output,
        error: error,
      );

      expect(exitCode, 0);
      expect(await File(goldenPath).readAsBytes(), <int>[4, 5]);
      expect(output.toString(), 'updated golden: $goldenPath\n');
      expect(error.toString(), isEmpty);
    });
  });
}
