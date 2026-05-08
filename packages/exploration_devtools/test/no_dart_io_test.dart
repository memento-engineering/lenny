@TestOn('vm')
library;

// This guard runs on the test VM purely to scan source files; it does
// not import dart:io into production code.
// ignore: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Forbidden import patterns. Matches `import 'dart:io'` and the variant
/// with double-quotes.
final _forbidden = RegExp(r'''import\s+['"]dart:io['"]''');

/// PRD §22: the DevTools extension must run in the browser. No source
/// file under `lib/` may transitively import `dart:io`.
void main() {
  test('no dart:io import in exploration_devtools/lib/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'Test must be run from the package root.');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (_forbidden.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files import dart:io but exploration_devtools is '
          'browser-targeted: $offenders',
    );
  });
}
