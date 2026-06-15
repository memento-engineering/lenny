/// Flutter harness: flutter_test, one test per shared check.
///
/// Calls the SAME framework-free check functions as
/// spike3_schema_roundtrip/test/spike3_test.dart does under plain
/// `dart test`. Same checks, two bindings — the "runs identically" proof
/// for genesis A2 + A3.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:spike3_schema_roundtrip/checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in allChecks.entries) {
    test(entry.key, entry.value);
  }
}
