import 'package:exploration_devtools/src/conversation/context_meter.dart';
import 'package:exploration_devtools/src/conversation/conversation_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows nothing when usage is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContextMeter(usage: null))),
    );
    expect(find.byKey(const Key('contextMeter.text')), findsNothing);
  });

  testWidgets(
    'renders ~2k / 32k for estimatedTokens=2000 trimThreshold=32000',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMeter(
              usage: const UsageSnapshot(
                estimatedTokens: 2000,
                trimThreshold: 32000,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('contextMeter.text')), findsOneWidget);
      expect(find.textContaining('~2k / 32k'), findsOneWidget);
    },
  );

  testWidgets('renders ~5k with no ceiling when trimThreshold is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextMeter(usage: const UsageSnapshot(estimatedTokens: 5000)),
        ),
      ),
    );
    expect(find.textContaining('~5k'), findsOneWidget);
    expect(find.textContaining('/'), findsNothing);
  });
}
