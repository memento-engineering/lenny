/// Filesystem helper shared by CLI screenshot writers.
library;

import 'dart:convert';
import 'dart:io';

/// Decodes [pngBase64], writes it to [path], and flushes it to disk.
///
/// Parent directories are created recursively. Invalid base64 is surfaced as
/// a [FormatException]. Returns the path reported by the written [File].
Future<String> writeBase64Png({
  required String path,
  required String pngBase64,
}) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(base64Decode(pngBase64), flush: true);
  return file.path;
}
