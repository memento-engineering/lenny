/// Bare-VM harness: package:test, one test per shared check.
///
/// The check bodies live in lib/checks.dart (framework-free, throw on
/// failure). The flutter harness in ../spike3_flutter_harness runs the SAME
/// functions under flutter_test.
library;

import 'package:spike3_schema_roundtrip/checks.dart';
import 'package:test/test.dart';

void main() {
  for (final entry in allChecks.entries) {
    test(entry.key, entry.value);
  }
}
