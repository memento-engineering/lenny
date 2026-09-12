import 'dart:io';

import 'package:grid_assets/grid_assets.dart' hide GridAssetsPack;
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('generated asset registry is current and declares the pack', () {
    final out = StringBuffer();
    final code = runGridAssetsGenerator(
      packageRoot: Directory.current.path,
      check: true,
      out: out,
    );
    expect(code, 0, reason: out.toString());
    expect(out.toString(), 'grid: 8 assets, 0 with an UNDECLARED selector\n');
    expect(
      [
        for (final asset in GridAssetsPack.definition.assets)
          (asset.assetKey.kind.name, asset.assetKey.id),
      ],
      [
        ('skill', 'test-with-leonard'),
        ('resource', 'plain-dart-flutter'),
        ('resource', 'widget'),
        ('resource', 'scripted-device'),
        ('resource', 'hardware'),
        ('resource', 'oracle'),
        ('resource', 'mutation'),
        ('resource', 'triage'),
      ],
    );

    final manifest =
        loadYaml(File('extension/mcp/config.yaml').readAsStringSync())
            as YamlMap;
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(manifest['name'], pubspec['name']);
  });
}
