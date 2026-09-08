/// Pure-Dart PNG golden comparison and baseline update support.
library;

import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Why an image golden comparison failed.
enum ImageGoldenFailureReason {
  /// The captured frame or golden file does not exist or cannot be read.
  missingFile,

  /// The captured frame or golden bytes do not decode as PNG.
  decodeFailure,

  /// The captured frame and golden have different dimensions.
  dimensionMismatch,

  /// More pixels differ than the configured maximum ratio permits.
  pixelDifference,
}

/// Immutable result for one captured-frame/golden pair.
@immutable
class ImageGoldenComparison {
  /// Creates a comparison result.
  const ImageGoldenComparison({
    required this.capturedPath,
    required this.goldenPath,
    required this.passed,
    this.failureReason,
    this.capturedWidth,
    this.capturedHeight,
    this.goldenWidth,
    this.goldenHeight,
    this.differingPixels,
    this.totalPixels,
  });

  /// Path to the frame captured during the current run.
  final String capturedPath;

  /// Path to the corresponding PNG baseline.
  final String goldenPath;

  /// Whether the captured frame satisfies the configured comparison.
  final bool passed;

  /// Failure category, or `null` when [passed] is true.
  final ImageGoldenFailureReason? failureReason;

  /// Captured image width when decoding succeeded.
  final int? capturedWidth;

  /// Captured image height when decoding succeeded.
  final int? capturedHeight;

  /// Golden image width when decoding succeeded.
  final int? goldenWidth;

  /// Golden image height when decoding succeeded.
  final int? goldenHeight;

  /// Number of differing pixels, or `null` when pixels were not visited.
  final int? differingPixels;

  /// Total comparable pixels, or `null` when pixels were not visited.
  final int? totalPixels;

  /// Ratio of differing pixels, or `null` when pixels were not visited.
  double? get diffRatio =>
      differingPixels == null || totalPixels == null || totalPixels == 0
      ? null
      : differingPixels! / totalPixels!;
}

/// Immutable ordered report for a set of frame comparisons.
@immutable
class ImageGoldenReport {
  /// Creates a report preserving [comparisons] order.
  ImageGoldenReport(Iterable<ImageGoldenComparison> comparisons)
    : comparisons = List<ImageGoldenComparison>.unmodifiable(comparisons);

  /// Per-frame comparison results in current-run trajectory order.
  final List<ImageGoldenComparison> comparisons;

  /// Process exit code: zero only when every frame passes.
  int get exitCode =>
      comparisons.every((comparison) => comparison.passed) ? 0 : 1;

  /// Renders one deterministic line for every failed comparison.
  String renderFailures() => comparisons
      .where((comparison) => !comparison.passed)
      .map(_renderFailure)
      .join('\n');

  static String _renderFailure(ImageGoldenComparison comparison) {
    final String paths =
        'captured=${comparison.capturedPath} golden=${comparison.goldenPath}';
    return switch (comparison.failureReason!) {
      ImageGoldenFailureReason.missingFile => 'missing image: $paths',
      ImageGoldenFailureReason.decodeFailure => 'invalid PNG: $paths',
      ImageGoldenFailureReason.dimensionMismatch =>
        'dimension mismatch: $paths '
            'captured_size=${comparison.capturedWidth}x${comparison.capturedHeight} '
            'golden_size=${comparison.goldenWidth}x${comparison.goldenHeight}',
      ImageGoldenFailureReason.pixelDifference =>
        'pixel difference: $paths '
            'differing=${comparison.differingPixels}/${comparison.totalPixels} '
            'ratio=${comparison.diffRatio}',
    };
  }
}

/// Compares decoded PNG frames with configurable channel and pixel tolerance.
class ImageGoldenComparator {
  /// Creates a comparator.
  ///
  /// [channelTolerance] must be between 0 and 255 inclusive, and
  /// [maxDiffRatio] must be finite and between 0.0 and 1.0 inclusive.
  ImageGoldenComparator({
    required this.channelTolerance,
    required this.maxDiffRatio,
  }) {
    if (channelTolerance < 0 || channelTolerance > 255) {
      throw RangeError.range(channelTolerance, 0, 255, 'channelTolerance');
    }
    if (!maxDiffRatio.isFinite || maxDiffRatio < 0 || maxDiffRatio > 1) {
      throw ArgumentError.value(maxDiffRatio, 'maxDiffRatio');
    }
  }

  /// Maximum allowed absolute difference for every RGBA channel.
  final int channelTolerance;

  /// Maximum allowed ratio of pixels exceeding [channelTolerance].
  final double maxDiffRatio;

  /// Compares one [capturedPath] with one [goldenPath].
  Future<ImageGoldenComparison> compareFrame({
    required String capturedPath,
    required String goldenPath,
  }) async {
    final File capturedFile = File(capturedPath);
    final File goldenFile = File(goldenPath);
    if (!await capturedFile.exists() || !await goldenFile.exists()) {
      return ImageGoldenComparison(
        capturedPath: capturedPath,
        goldenPath: goldenPath,
        passed: false,
        failureReason: ImageGoldenFailureReason.missingFile,
      );
    }

    final image.Image? captured;
    final image.Image? golden;
    try {
      captured = image.decodePng(await capturedFile.readAsBytes());
      golden = image.decodePng(await goldenFile.readAsBytes());
    } on FileSystemException {
      return ImageGoldenComparison(
        capturedPath: capturedPath,
        goldenPath: goldenPath,
        passed: false,
        failureReason: ImageGoldenFailureReason.missingFile,
      );
    } on Object {
      return ImageGoldenComparison(
        capturedPath: capturedPath,
        goldenPath: goldenPath,
        passed: false,
        failureReason: ImageGoldenFailureReason.decodeFailure,
      );
    }
    if (captured == null || golden == null) {
      return ImageGoldenComparison(
        capturedPath: capturedPath,
        goldenPath: goldenPath,
        passed: false,
        failureReason: ImageGoldenFailureReason.decodeFailure,
      );
    }

    if (captured.width != golden.width || captured.height != golden.height) {
      return ImageGoldenComparison(
        capturedPath: capturedPath,
        goldenPath: goldenPath,
        passed: false,
        failureReason: ImageGoldenFailureReason.dimensionMismatch,
        capturedWidth: captured.width,
        capturedHeight: captured.height,
        goldenWidth: golden.width,
        goldenHeight: golden.height,
      );
    }

    var differingPixels = 0;
    for (var y = 0; y < captured.height; y++) {
      for (var x = 0; x < captured.width; x++) {
        final image.Pixel actual = captured.getPixel(x, y);
        final image.Pixel expected = golden.getPixel(x, y);
        if (_channelDiffers(actual.r, expected.r) ||
            _channelDiffers(actual.g, expected.g) ||
            _channelDiffers(actual.b, expected.b) ||
            _channelDiffers(actual.a, expected.a)) {
          differingPixels++;
        }
      }
    }
    final int totalPixels = captured.width * captured.height;
    final double ratio = totalPixels == 0 ? 0.0 : differingPixels / totalPixels;
    final bool passed = ratio <= maxDiffRatio;
    return ImageGoldenComparison(
      capturedPath: capturedPath,
      goldenPath: goldenPath,
      passed: passed,
      failureReason: passed ? null : ImageGoldenFailureReason.pixelDifference,
      capturedWidth: captured.width,
      capturedHeight: captured.height,
      goldenWidth: golden.width,
      goldenHeight: golden.height,
      differingPixels: differingPixels,
      totalPixels: totalPixels,
    );
  }

  /// Compares explicit current-run [framePaths] with same-named goldens.
  ///
  /// Neither directory is scanned, so stale files do not enter the report.
  Future<ImageGoldenReport> compareFrames({
    required Iterable<String> framePaths,
    required String goldensDirectory,
  }) async {
    final List<ImageGoldenComparison> comparisons = <ImageGoldenComparison>[];
    for (final String framePath in framePaths) {
      comparisons.add(
        await compareFrame(
          capturedPath: framePath,
          goldenPath: p.join(goldensDirectory, p.basename(framePath)),
        ),
      );
    }
    return ImageGoldenReport(comparisons);
  }

  bool _channelDiffers(num actual, num expected) =>
      (actual - expected).abs() > channelTolerance;
}

/// Creates or overwrites same-named baselines for explicit [framePaths].
///
/// Bytes are copied without decoding. Returned paths preserve input order.
Future<List<String>> updateImageGoldens({
  required Iterable<String> framePaths,
  required String goldensDirectory,
}) async {
  await Directory(goldensDirectory).create(recursive: true);
  final List<String> writtenPaths = <String>[];
  for (final String framePath in framePaths) {
    final String goldenPath = p.join(goldensDirectory, p.basename(framePath));
    await File(
      goldenPath,
    ).writeAsBytes(await File(framePath).readAsBytes(), flush: true);
    writtenPaths.add(goldenPath);
  }
  return List<String>.unmodifiable(writtenPaths);
}

/// Finishes a run by updating baselines or comparing frames, never both.
///
/// Update receipts go to [output]. Comparison failures go to [error].
Future<int> finishImageGoldenRun({
  required Iterable<String> framePaths,
  required String goldensDirectory,
  required int channelTolerance,
  required double maxDiffRatio,
  required bool updateGoldens,
  required StringSink output,
  required StringSink error,
}) async {
  if (updateGoldens) {
    final List<String> writtenPaths = await updateImageGoldens(
      framePaths: framePaths,
      goldensDirectory: goldensDirectory,
    );
    for (final String path in writtenPaths) {
      output.writeln('updated golden: $path');
    }
    return 0;
  }

  final ImageGoldenReport report = await ImageGoldenComparator(
    channelTolerance: channelTolerance,
    maxDiffRatio: maxDiffRatio,
  ).compareFrames(framePaths: framePaths, goldensDirectory: goldensDirectory);
  final String failures = report.renderFailures();
  if (failures.isNotEmpty) error.writeln(failures);
  return report.exitCode;
}
