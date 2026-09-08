/// Trajectory sink decorator that persists screenshots already in turn records.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart' show TrajectorySink;
import 'package:path/path.dart' as p;

import 'png_file_writer.dart';

/// Writes trajectory lines unchanged and extracts observation PNG frames.
///
/// Only turn records with an integer `index` and a non-empty
/// `observation.screenshot_png_b64` value produce a file. All other records,
/// including malformed JSON, are forwarded and ignored for frame capture.
class FrameCaptureSink implements TrajectorySink {
  /// Creates a frame-capturing decorator around [delegate].
  FrameCaptureSink({required this.delegate, required this.framesDirectory});

  /// The trajectory sink that receives every input line unchanged.
  final TrajectorySink delegate;

  /// Directory where captured frames are written.
  final String framesDirectory;

  final List<String> _capturedFramePaths = <String>[];

  /// Unmodifiable live view of frame paths in trajectory order.
  List<String> get capturedFramePaths =>
      UnmodifiableListView<String>(_capturedFramePaths);

  @override
  Future<void> writeLine(String line) async {
    await delegate.writeLine(line);

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'turn') {
      return;
    }
    final Object? index = decoded['index'];
    final Object? observation = decoded['observation'];
    if (index is! int || observation is! Map) return;
    final Object? pngBase64 = observation['screenshot_png_b64'];
    if (pngBase64 is! String || pngBase64.isEmpty) return;

    final String framePath = p.join(
      framesDirectory,
      'turn-${index.toString().padLeft(4, '0')}.png',
    );
    final String writtenPath = await writeBase64Png(
      path: framePath,
      pngBase64: pngBase64,
    );
    _capturedFramePaths.add(writtenPath);
  }

  @override
  Future<void> flush() => delegate.flush();

  @override
  Future<void> close() => delegate.close();
}
