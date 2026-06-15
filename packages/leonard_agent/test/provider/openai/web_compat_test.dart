@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('OpenAI provider sources contain no dart:io import', () async {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:leonard_agent/leonard_agent.dart'),
    );
    expect(libUri, isNotNull,
        reason: 'could not resolve leonard_agent package URI');
    final libFile = File.fromUri(libUri!);
    final packageRoot = libFile.parent.parent;
    final providerDir =
        Directory('${packageRoot.path}/lib/src/provider/openai');
    expect(providerDir.existsSync(), isTrue,
        reason: 'expected OpenAI provider dir at ${providerDir.path}');

    final offenders = <String>[];
    await for (final f in providerDir.list(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = await f.readAsString();
      if (src.contains("'dart:io'") || src.contains('"dart:io"')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'OpenAI provider must remain web-compatible');
  });
}
