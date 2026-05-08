import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tabs render three tabs with Prompt selected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(vmServiceUri: () => null),
    ));
    await tester.pump();

    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    // The Prompt tab is selected by default, so its placeholder body is
    // mounted (the others are off-screen in the TabBarView).
    expect(find.textContaining('lenny-cx6.22'), findsOneWidget);
  });
}
