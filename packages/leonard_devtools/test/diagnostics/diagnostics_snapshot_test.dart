import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:leonard_devtools/leonard_devtools.dart';

void main() {
  final TreeSnapshot snapshot = TreeSnapshot(
    contractVersion: 1,
    projectedAt: DateTime.utc(2026, 8, 1),
    root: const TreeNode(
      seedType: 'Root',
      id: 'root',
      properties: <DiagnosticsProperty>[
        DiagnosticsProperty.flag(
          name: 'ready',
          level: DiagnosticsLevel.info,
          value: true,
        ),
      ],
      children: <TreeNode>[
        TreeNode(
          seedType: 'Leaf',
          id: 'leaf',
          properties: <DiagnosticsProperty>[],
          children: <TreeNode>[],
        ),
      ],
    ),
  );

  Map<String, Object?> bare() => <String, Object?>{
    'diagnostics_tree': snapshot.toJson(),
  };

  test('decodes a bare get_diagnostics_tree response', () {
    expect(decodeDiagnosticsSnapshot(bare()), snapshot);
  });

  test('decodes a value-wrapped get_diagnostics_tree response', () {
    expect(
      decodeDiagnosticsSnapshot(<String, Object?>{'value': bare()}),
      snapshot,
    );
  });

  test('missing diagnostics_tree throws FormatException', () {
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{}),
      throwsFormatException,
    );
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'value': <String, Object?>{},
      }),
      throwsFormatException,
    );
  });

  test('non-map diagnostics_tree throws FormatException', () {
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'diagnostics_tree': 'not a map',
      }),
      throwsFormatException,
    );
  });

  test('unsupported contract version throws FormatException', () {
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'diagnostics_tree': <String, Object?>{
          ...snapshot.toJson(),
          'contractVersion': 2,
        },
      }),
      throwsFormatException,
    );
  });

  test('invalid projectedAt timestamp throws FormatException', () {
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'diagnostics_tree': <String, Object?>{
          ...snapshot.toJson(),
          'projectedAt': 'nope',
        },
      }),
      throwsFormatException,
    );
  });

  test('malformed node throws FormatException', () {
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'diagnostics_tree': <String, Object?>{
          ...snapshot.toJson(),
          'root': <String, Object?>{
            // Missing seedType/id/properties/children.
            'bogus': true,
          },
        },
      }),
      throwsFormatException,
    );
  });

  test('malformed property throws FormatException', () {
    final Map<String, Object?> tree = snapshot.toJson();
    final Map<String, Object?> root = Map<String, Object?>.from(
      tree['root']! as Map<String, Object?>,
    );
    root['properties'] = <Object?>[
      <String, Object?>{
        'kind': 'unknown-kind',
        'name': 'ready',
        'level': 'info',
      },
    ];
    expect(
      () => decodeDiagnosticsSnapshot(<String, Object?>{
        'diagnostics_tree': <String, Object?>{...tree, 'root': root},
      }),
      throwsFormatException,
    );
  });
}
