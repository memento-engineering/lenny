@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('provider sources contain no dart:io import', () async {
    // Resolve the package root via the Dart package config so the
    // assertion works regardless of the cwd `dart test` was launched in.
    final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:leonard_agent/leonard_agent.dart'));
    expect(libUri, isNotNull,
        reason: 'could not resolve leonard_agent package URI');
    // libUri => <packageRoot>/lib/leonard_agent.dart
    final libFile = File.fromUri(libUri!);
    final packageRoot = libFile.parent.parent;
    final providerDir = Directory('${packageRoot.path}/lib/src/provider');
    expect(providerDir.existsSync(), isTrue,
        reason: 'expected provider dir at ${providerDir.path}');

    final offenders = <String>[];
    await for (final f in providerDir.list(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = await f.readAsString();
      if (src.contains("'dart:io'") || src.contains('"dart:io"')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'leonard_agent provider must remain web-compatible');
  });
}
