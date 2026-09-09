// This fixture intentionally includes other-package and missing imports.
// ignore_for_file: uri_does_not_exist, undefined_identifier, depend_on_referenced_packages

import 'package:another_package/ignored.dart';
import 'package:test_impact_fixture/generated.missing.dart';
import 'package:test_impact_fixture/unrelated.dart';

void main() {
  unrelatedValue;
}
