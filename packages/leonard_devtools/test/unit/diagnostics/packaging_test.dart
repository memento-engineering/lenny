import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'leonard_flutter bundle discovers diagnostics without grid packages',
    () {
      final String config = File(
        '../leonard_flutter/extension/devtools/config.yaml',
      ).readAsStringSync();
      final String bundle = File(
        '../leonard_flutter/extension/devtools/build/main.dart.js',
      ).readAsStringSync();
      expect(config, contains('name: leonard'));
      expect(bundle, contains('Diagnostics'));
      expect(bundle, contains('diagnostics_tree'));
      expect(bundle, contains('ext.leonard.core.get_diagnostics_tree'));
      expect(_gridPackageReferences(), isEmpty);
    },
  );
}

List<String> _gridPackageReferences() {
  final List<File> sources = <File>[
    File('pubspec.yaml'),
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart')),
  ];
  final RegExp gridReference = RegExp(r'(^|package:)grid_');
  return <String>[
    for (final File file in sources)
      for (final String line in file.readAsLinesSync())
        if (gridReference.hasMatch(line)) '${file.path}:$line',
  ];
}
