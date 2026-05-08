@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('frontier + anthropic sources contain no dart:io import', () async {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:exploration_agent/exploration_agent.dart'),
    );
    expect(libUri, isNotNull,
        reason: 'could not resolve exploration_agent package URI');
    final libFile = File.fromUri(libUri!);
    final packageRoot = libFile.parent.parent;

    final roots = <String>[
      '${packageRoot.path}/lib/src/provider/frontier',
      '${packageRoot.path}/lib/src/provider/anthropic',
    ];
    final offenders = <String>[];
    for (final rootPath in roots) {
      final dir = Directory(rootPath);
      expect(dir.existsSync(), isTrue,
          reason: 'expected dir at $rootPath');
      await for (final f in dir.list(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = await f.readAsString();
        if (src.contains("'dart:io'") || src.contains('"dart:io"')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'frontier/anthropic provider sources must stay web-compatible');
  });
}
