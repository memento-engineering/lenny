import 'dart:convert';
import 'dart:io';

import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Defensive guard: tokens / api keys never leak through `toString` or
/// `toJsonRedacted`, and nothing in the panel package prints/debugPrints
/// a field that might carry a secret.
void main() {
  const sentinel = 'sentinel-DO-NOT-LEAK-12345';

  group('toString / toJsonRedacted', () {
    test('swift-infer never leaks bearer', () {
      final cfg = SwiftInferUiConfig(
        bearerToken: sentinel,
        endpoint: Uri.parse('http://localhost:8080'),
      );
      expect(cfg.toString().contains(sentinel), isFalse);
      expect(jsonEncode(cfg.toJsonRedacted()).contains(sentinel), isFalse);
    });

    test('anthropic never leaks apiKey', () {
      final cfg = AnthropicUiConfig(apiKey: sentinel);
      expect(cfg.toString().contains(sentinel), isFalse);
      expect(jsonEncode(cfg.toJsonRedacted()).contains(sentinel), isFalse);
    });

    test('openai never leaks apiKey', () {
      final cfg = OpenAiUiConfig(apiKey: sentinel);
      expect(cfg.toString().contains(sentinel), isFalse);
      expect(jsonEncode(cfg.toJsonRedacted()).contains(sentinel), isFalse);
    });
  });

  test('panel package never print()s or debugPrint()s token/key fields',
      () async {
    final libDir =
        Directory('packages/leonard_devtools/lib/src/panels').existsSync()
            ? Directory('packages/leonard_devtools/lib/src/panels')
            : Directory('lib/src/panels');
    expect(libDir.existsSync(), isTrue,
        reason: 'expected to find the panels lib directory; cwd=${Directory.current.path}');
    final offenders = <String>[];
    for (final f in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      // Strip line comments and block comments so doc-strings don't
      // false-positive.
      final stripped = src
          .replaceAll(RegExp(r'//[^\n]*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final hasPrint = RegExp(r'\b(print|debugPrint)\s*\(').hasMatch(l);
        if (!hasPrint) continue;
        // Anything print-y in panel code is a smell; flag it. Whitelisted
        // by adding `// print-allowed: <reason>` on the same line.
        if (l.contains('print-allowed:')) continue;
        offenders.add('${f.path}:${i + 1}: ${l.trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'panel code must not print()/debugPrint(); '
            'add `// print-allowed: <reason>` to whitelist.\n'
            '${offenders.join('\n')}');
  });
}
