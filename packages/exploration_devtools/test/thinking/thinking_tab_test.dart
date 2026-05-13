import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/panels/thinking_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Thinking tab shows "No active session" hint when no session',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExplorationShell(
            manifestProbe: () async => const [],
            sessionFactory: () async => throw StateError('no session'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();

      // The mount widget is present; without a session it falls back to
      // the "No active session" hint instead of the live panel.
      expect(find.byType(ThinkingPlaceholder), findsOneWidget);
      expect(find.text('No active session'), findsOneWidget);
    },
  );
}
