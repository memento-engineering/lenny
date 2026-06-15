import 'dart:convert';
import 'dart:typed_data';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/timeline/turn_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TurnRecord _turn({
  int index = 0,
  Map<String, dynamic>? observation,
  Map<String, dynamic>? proposed,
  Map<String, dynamic>? executed,
  Map<String, dynamic>? validation,
  Map<String, dynamic>? modelMetadata,
}) =>
    TurnRecord(
      index: index,
      observation: observation ??
          const {
            'core': <String, dynamic>{
              'route_stack': ['Home', 'Login'],
              'nodes': [
                {'id': 1, 'label': 'submit'},
                {'id': 2, 'label': 'cancel'},
              ],
            },
            'extensions': <String, dynamic>{
              'router': {'route': '/login'},
            },
          },
      stability: const {'policy': 'action_relative'},
      proposedAction: proposed ?? const {'tool': 'core.tap', 'args': {'id': 'submit'}},
      validation: validation ?? const {'result': 'ok', 'retries': 0},
      executedAction: executed ?? const {'tool': 'core.tap', 'args': {'id': 'submit'}},
      diff: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      modelMetadata: modelMetadata ?? const {'reasoning': 'tap submit to log in'},
    );

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('TurnDetailView', () {
    testWidgets('renders action, validation, reasoning and route stack', (tester) async {
      await tester.pumpWidget(_wrap(TurnDetailView(record: _turn(index: 3))));

      expect(find.text('Turn #3'), findsOneWidget);
      expect(find.textContaining('core.tap('), findsWidgets);
      expect(find.textContaining('"id":"submit"'), findsWidgets);
      expect(find.text('OK (retries 0)'), findsOneWidget);
      expect(find.text('tap submit to log in'), findsOneWidget);
      expect(find.text('Home -> Login'), findsOneWidget);
      expect(find.textContaining('Semantics nodes (2)'), findsOneWidget);
    });

    testWidgets('reports rejected validation with reason and retries', (tester) async {
      await tester.pumpWidget(_wrap(TurnDetailView(
        record: _turn(
          validation: const {'result': 'unstable', 'retries': 3},
        ),
      )));
      expect(find.text('Rejected: unstable (retries 3)'), findsOneWidget);
    });

    testWidgets('falls back to "(none)" when no reasoning provided', (tester) async {
      await tester.pumpWidget(_wrap(TurnDetailView(
        record: _turn(modelMetadata: const {}),
      )));
      expect(find.text('(none)'), findsOneWidget);
    });

    testWidgets('renders plugin fragments as expandable JSON sections', (tester) async {
      await tester.pumpWidget(_wrap(TurnDetailView(record: _turn())));
      expect(find.text('Plugin: router'), findsOneWidget);
      // Body of the ExpansionTile is collapsed by default.
      expect(find.textContaining('"route": "/login"'), findsNothing);
    });

    testWidgets('semantics JSON is not rendered until expansion tile is tapped',
        (tester) async {
      await tester.pumpWidget(_wrap(TurnDetailView(record: _turn())));
      // Long JSON output should not be in the tree while collapsed.
      expect(find.textContaining('"label": "submit"'), findsNothing);

      await tester.tap(find.text('Show JSON').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('"label": "submit"'), findsOneWidget);
    });

    testWidgets('screenshot decoded only when expanded', (tester) async {
      // 1MB-ish base64 payload (we won't actually decode it; we just count
      // calls to the indirected decoder).
      final big = base64Encode(Uint8List(1024 * 1024));
      var decodes = 0;
      Uint8List recorder(String b) {
        decodes++;
        // Return a 1x1 PNG so Image.memory doesn't throw when finally rendered.
        return Uint8List.fromList(const [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82,
        ]);
      }

      final record = TurnRecord(
        index: 0,
        observation: {
          'core': {'screenshot_base64': big, 'route_stack': <String>[], 'nodes': <dynamic>[]},
          'extensions': const <String, dynamic>{},
        },
        stability: const {},
        proposedAction: const {'tool': 'core.tap'},
        validation: const {'result': 'ok'},
        executedAction: const {'tool': 'core.tap'},
        diff: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
        modelMetadata: const {},
      );

      await tester.pumpWidget(_wrap(
        TurnDetailView(record: record, screenshotDecoder: recorder),
      ));
      // Initial pump and a few extra pumps — even with multiple frames, no
      // decode should fire while the Show image tile is collapsed.
      await tester.pump();
      await tester.pump();
      expect(decodes, 0);

      await tester.tap(find.text('Show image'));
      await tester.pumpAndSettle();
      expect(decodes, 1);
    });
  });
}
