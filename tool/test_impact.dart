import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Writes one mutation-test input document per selected production source.
///
/// The positional interface is:
///
///     dart run tool/test_impact.dart PACKAGE_DIR OUTPUT_DIR SOURCE...
///
/// Sources are package-relative `lib/**/*.dart` paths. On success, stdout is a
/// manifest containing only the absolute document paths, one per line.
void main(List<String> arguments) {
  try {
    final List<String> manifest = _generate(arguments);
    stdout.write(manifest.map((String path) => '$path\n').join());
  } on _CliFailure catch (failure) {
    stderr.writeln('error: ${failure.message}');
    exitCode = failure.code;
  }
}

List<String> _generate(List<String> arguments) {
  if (arguments.length < 3) {
    throw const _CliFailure(
      64,
      'usage: test_impact.dart PACKAGE_DIR OUTPUT_DIR SOURCE...',
    );
  }

  final Directory packageDirectory = Directory(arguments[0]).absolute;
  if (!packageDirectory.existsSync()) {
    throw _CliFailure(66, 'package not found: ${arguments[0]}');
  }
  final File pubspec = File('${packageDirectory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw _CliFailure(66, 'pubspec.yaml not found: ${pubspec.path}');
  }

  final Directory outputDirectory = Directory(arguments[1]).absolute;
  if (!outputDirectory.parent.existsSync()) {
    throw _CliFailure(
      66,
      'output parent not found: ${outputDirectory.parent.path}',
    );
  }

  final List<String> sources = arguments.sublist(2);
  final Set<String> uniqueSources = <String>{};
  for (final String source in sources) {
    if (!_isProductionSource(source)) {
      throw _CliFailure(
        64,
        'source must be a package-relative lib/**/*.dart path: $source',
      );
    }
    if (!uniqueSources.add(source)) {
      throw _CliFailure(64, 'duplicate source: $source');
    }
    if (!File('${packageDirectory.path}/$source').existsSync()) {
      throw _CliFailure(66, 'source not found: $source');
    }
  }
  sources.sort();

  final String packageName = _readPackageName(pubspec);
  final _ImportGraph graph = _ImportGraph(packageDirectory, packageName);
  final List<String> tests = _findTests(packageDirectory);

  outputDirectory.createSync();
  for (final FileSystemEntity entry in outputDirectory.listSync()) {
    if (entry is File && entry.path.endsWith('.xml')) {
      entry.deleteSync();
    }
  }

  final List<String> manifest = <String>[];
  for (var index = 0; index < sources.length; index++) {
    final String source = sources[index];
    final String absoluteSource = graph.absolutePath(source);
    final bool isBarrel = graph.node(absoluteSource).isBarrel;
    final List<String> impactedTests =
        isBarrel
              ? <String>[]
              : tests
                    .where((String test) => graph.reaches(test, absoluteSource))
                    .map(graph.packageRelativePath)
                    .toSet()
                    .toList()
          ..sort();
    final String command = impactedTests.isEmpty
        ? 'dart test'
        : 'dart test ${impactedTests.map(_posixQuote).join(' ')}';
    final String sanitized = source.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
    final String documentName =
        '${index.toString().padLeft(3, '0')}-$sanitized.xml';
    final File document = File('${outputDirectory.path}/$documentName');
    document.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<mutations version="1.2">
  <files>
    <file>${_xmlEscape(source)}</file>
  </files>
  <commands>
    <command group="test" expected-return="0" working-directory=".">${_xmlEscape(command)}</command>
  </commands>
</mutations>
''');
    manifest.add(document.absolute.path);
  }
  return manifest;
}

bool _isProductionSource(String source) {
  if (source.startsWith('/') || source.contains('\\')) return false;
  final List<String> segments = source.split('/');
  return segments.length >= 2 &&
      segments.first == 'lib' &&
      segments.every(
        (String segment) =>
            segment.isNotEmpty && segment != '.' && segment != '..',
      ) &&
      segments.last.endsWith('.dart');
}

String _readPackageName(File pubspec) {
  final RegExpMatch? match = RegExp(
    r'^name:\s*([a-z][a-z0-9_]*)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    throw const _CliFailure(66, 'pubspec.yaml has no valid package name');
  }
  return match.group(1)!;
}

List<String> _findTests(Directory packageDirectory) {
  final Directory testDirectory = Directory('${packageDirectory.path}/test');
  if (!testDirectory.existsSync()) return <String>[];
  final List<String> tests = testDirectory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((File file) => file.absolute.path)
      .where((String path) => path.endsWith('_test.dart'))
      .toList();
  tests.sort();
  return tests;
}

String _posixQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

final class _ImportGraph {
  _ImportGraph(this.packageDirectory, this.packageName);

  final Directory packageDirectory;
  final String packageName;
  final Map<String, _Node> _nodes = <String, _Node>{};

  String absolutePath(String packageRelativePath) =>
      File('${packageDirectory.path}/$packageRelativePath').absolute.path;

  String packageRelativePath(String absolutePath) =>
      absolutePath.substring(packageDirectory.absolute.path.length + 1);

  _Node node(String path) => _nodes.putIfAbsent(path, () => _parse(path));

  bool reaches(String start, String target) {
    final Set<String> visited = <String>{};
    bool walk(String current) {
      if (!visited.add(current)) return false;
      if (current == target) return true;
      return node(current).dependencies.any(walk);
    }

    return walk(start);
  }

  _Node _parse(String path) {
    final CompilationUnit unit = parseFile(
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    final List<String> dependencies = <String>[];
    var isBarrel = false;
    for (final Directive directive in unit.directives) {
      if (directive is ExportDirective) isBarrel = true;
      if (directive is! UriBasedDirective) continue;
      final String? literal = directive.uri.stringValue;
      if (literal == null) continue;
      final String? dependency = _resolve(path, literal);
      if (dependency != null) dependencies.add(dependency);
    }
    dependencies.sort();
    return _Node(dependencies.toSet().toList(), isBarrel);
  }

  String? _resolve(String importer, String literal) {
    final Uri uri;
    try {
      uri = Uri.parse(literal);
    } on FormatException {
      return null;
    }
    if (uri.hasQuery || uri.hasFragment) return null;

    String? candidate;
    if (uri.scheme == 'package') {
      final List<String> segments = uri.pathSegments;
      if (segments.length < 2 || segments.first != packageName) return null;
      final List<String> relative = segments.skip(1).toList();
      if (relative.any(
        (String segment) =>
            segment.isEmpty || segment == '.' || segment == '..',
      )) {
        return null;
      }
      candidate = absolutePath('lib/${relative.join('/')}');
    } else if (uri.scheme.isEmpty) {
      candidate = File.fromUri(
        File(importer).uri.resolveUri(uri),
      ).absolute.path;
    } else {
      return null;
    }

    final String packagePrefix = '${packageDirectory.absolute.path}/';
    if (!candidate.startsWith(packagePrefix) || !candidate.endsWith('.dart')) {
      return null;
    }
    return File(candidate).existsSync() ? candidate : null;
  }
}

final class _Node {
  const _Node(this.dependencies, this.isBarrel);

  final List<String> dependencies;
  final bool isBarrel;
}

final class _CliFailure implements Exception {
  const _CliFailure(this.code, this.message);

  final int code;
  final String message;
}
