// This fixture is parsed without package resolution by tool/test_impact.dart.
// ignore_for_file: uri_does_not_exist, undefined_identifier, avoid_relative_lib_imports

import 'package:test_impact_fixture/left.dart';
import '../lib/right.dart';

void main() {
  leftValue + rightValue;
}
