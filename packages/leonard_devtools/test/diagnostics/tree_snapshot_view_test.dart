import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:leonard_devtools/leonard_devtools.dart';

final DateTime _epoch = DateTime.utc(2026, 8, 1);

/// Every property constructor variant, spanning all four
/// [DiagnosticsLevel] values, plus a nested object.
final List<DiagnosticsProperty> _everyVariant = <DiagnosticsProperty>[
  const DiagnosticsProperty.string(
    name: 's',
    level: DiagnosticsLevel.fine,
    value: 'v',
  ),
  const DiagnosticsProperty.int(
    name: 'i',
    level: DiagnosticsLevel.info,
    value: 1,
  ),
  const DiagnosticsProperty.double(
    name: 'd',
    level: DiagnosticsLevel.warning,
    value: 1.5,
  ),
  const DiagnosticsProperty.flag(
    name: 'f',
    level: DiagnosticsLevel.error,
    value: true,
  ),
  const DiagnosticsProperty.enumValue(
    name: 'e',
    level: DiagnosticsLevel.fine,
    enumType: 'Mode',
    value: 'on',
  ),
  const DiagnosticsProperty.duration(
    name: 'du',
    level: DiagnosticsLevel.info,
    value: Duration(seconds: 2),
  ),
  DiagnosticsProperty.timestamp(
    name: 'ts',
    level: DiagnosticsLevel.warning,
    value: _epoch,
  ),
  const DiagnosticsProperty.reference(
    name: 'r',
    level: DiagnosticsLevel.error,
    referenceKind: ReferenceKind.bead,
    value: '42',
  ),
  const DiagnosticsProperty.object(
    name: 'o',
    level: DiagnosticsLevel.info,
    properties: <DiagnosticsProperty>[],
  ),
  const DiagnosticsProperty.object(
    name: 'nested',
    level: DiagnosticsLevel.warning,
    properties: <DiagnosticsProperty>[
      DiagnosticsProperty.flag(
        name: 'ready',
        level: DiagnosticsLevel.info,
        value: true,
      ),
    ],
  ),
];

/// One immutable fixture: a root carrying every property variant, a
/// parent, and a leaf.
final TreeSnapshot _fixture = TreeSnapshot(
  contractVersion: 1,
  projectedAt: _epoch,
  root: TreeNode(
    seedType: 'Root',
    id: 'root',
    properties: _everyVariant,
    children: const <TreeNode>[
      TreeNode(
        seedType: 'Parent',
        id: 'parent',
        properties: <DiagnosticsProperty>[],
        children: <TreeNode>[
          TreeNode(
            seedType: 'Leaf',
            id: 'leaf',
            properties: <DiagnosticsProperty>[],
            children: <TreeNode>[],
          ),
        ],
      ),
    ],
  ),
);

String _detailsId(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const Key('diagnostics.details.id')))
    .data!;

void main() {
  testWidgets('renders every property row recursively for the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TreeSnapshotView(snapshot: _fixture)),
    );
    // Root is selected by default; every property row renders, and the
    // nested object's child rows render recursively.
    expect(_detailsId(tester), 'root');
    expect(find.text('s: v'), findsOneWidget);
    expect(find.text('i: 1'), findsOneWidget);
    expect(find.text('d: 1.5'), findsOneWidget);
    expect(find.text('f: true'), findsOneWidget);
    expect(find.text('e: Mode.on'), findsOneWidget);
    expect(find.text('du: 0:00:02.000000'), findsOneWidget);
    expect(find.text('ts: 2026-08-01T00:00:00.000Z'), findsOneWidget);
    expect(find.text('r: bead:42'), findsOneWidget);
    expect(find.text('o: 0 properties'), findsOneWidget);
    expect(find.text('nested: 1 properties'), findsOneWidget);
    expect(find.text('ready: true'), findsOneWidget);
  });

  testWidgets('expands, collapses, and selects nodes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TreeSnapshotView(snapshot: _fixture)),
    );
    // Collapsed: only the root row is visible.
    expect(find.byKey(const Key('diagnostics.node.root')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics.node.parent')), findsNothing);
    // Expand root → parent appears; expand parent → leaf appears.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.byKey(const Key('diagnostics.node.parent')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics.node.leaf')), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.byKey(const Key('diagnostics.node.leaf')), findsOneWidget);
    // Select the leaf.
    await tester.tap(find.byKey(const Key('diagnostics.node.leaf')));
    await tester.pump();
    expect(_detailsId(tester), 'leaf');
    // Collapse root → the whole subtree hides again.
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pump();
    expect(find.byKey(const Key('diagnostics.node.parent')), findsNothing);
    expect(find.byKey(const Key('diagnostics.node.leaf')), findsNothing);
  });

  testWidgets(
    'retains the selection when its id survives a replacement snapshot '
    'and falls back to root when it disappears',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: TreeSnapshotView(snapshot: _fixture)),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.tap(find.byKey(const Key('diagnostics.node.parent')));
      await tester.pump();
      expect(_detailsId(tester), 'parent');

      // Replacement snapshot that still contains 'parent'.
      final TreeSnapshot replacement = TreeSnapshot(
        contractVersion: 1,
        projectedAt: _epoch,
        root: const TreeNode(
          seedType: 'Root',
          id: 'root',
          properties: <DiagnosticsProperty>[],
          children: <TreeNode>[
            TreeNode(
              seedType: 'Parent',
              id: 'parent',
              properties: <DiagnosticsProperty>[],
              children: <TreeNode>[],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: TreeSnapshotView(snapshot: replacement)),
      );
      expect(_detailsId(tester), 'parent');

      // Replacement snapshot without 'parent' → fall back to root.
      final TreeSnapshot withoutParent = TreeSnapshot(
        contractVersion: 1,
        projectedAt: _epoch,
        root: const TreeNode(
          seedType: 'Root',
          id: 'root',
          properties: <DiagnosticsProperty>[],
          children: <TreeNode>[],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: TreeSnapshotView(snapshot: withoutParent)),
      );
      expect(_detailsId(tester), 'root');
    },
  );

  test('formats every property variant', () {
    final List<String> formatted = <String>[
      for (final DiagnosticsProperty property in _everyVariant)
        diagnosticsPropertyValue(property),
    ];
    expect(formatted, <String>[
      'v',
      '1',
      '1.5',
      'true',
      'Mode.on',
      '0:00:02.000000',
      '2026-08-01T00:00:00.000Z',
      'bead:42',
      '0 properties',
      '1 properties',
    ]);
  });

  test('maps every severity to its icon', () {
    expect(diagnosticsLevelIcon(DiagnosticsLevel.fine), Icons.tune);
    expect(diagnosticsLevelIcon(DiagnosticsLevel.info), Icons.info_outline);
    expect(
      diagnosticsLevelIcon(DiagnosticsLevel.warning),
      Icons.warning_amber,
    );
    expect(diagnosticsLevelIcon(DiagnosticsLevel.error), Icons.error_outline);
  });

  testWidgets('maps every severity to a theme-aware color', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final ColorScheme scheme = Theme.of(context).colorScheme;
    expect(
      diagnosticsLevelColor(context, DiagnosticsLevel.fine),
      scheme.outline,
    );
    expect(
      diagnosticsLevelColor(context, DiagnosticsLevel.info),
      scheme.primary,
    );
    expect(
      diagnosticsLevelColor(context, DiagnosticsLevel.warning),
      Colors.orange,
    );
    expect(
      diagnosticsLevelColor(context, DiagnosticsLevel.error),
      scheme.error,
    );
  });
}
