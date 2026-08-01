import 'package:leonard_devtools/src/conversation/conversation_entry_view.dart';
import 'package:leonard_devtools/src/conversation/conversation_state.dart';
import 'package:leonard_devtools/src/thinking/append_only_text_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationEntryView', () {
    testWidgets('renders thinking text from live controller', (tester) async {
      final ctl = AppendOnlyTextController()..append('thinking live');
      addTearDown(ctl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationEntryView(
              entry: const ConversationEntry(turnIndex: 0),
              thinkingController: ctl,
            ),
          ),
        ),
      );
      expect(find.text('thinking live'), findsOneWidget);
    });

    testWidgets('renders tool-call chip when toolName is set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationEntryView(
              entry: const ConversationEntry(
                turnIndex: 0,
                toolName: 'core.tap',
                toolArgs: {'element': 'btn'},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('toolcall.0')), findsOneWidget);
      expect(find.textContaining('core.tap'), findsOneWidget);
    });

    testWidgets('renders tool result card when complete', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationEntryView(
              entry: const ConversationEntry(
                turnIndex: 0,
                toolName: 'core.tap',
                toolResult: '✓ ok',
                complete: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('result.0')), findsOneWidget);
      expect(find.textContaining('✓ ok'), findsOneWidget);
    });

    testWidgets('does not show result card when not complete', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationEntryView(
              entry: const ConversationEntry(
                turnIndex: 0,
                toolName: 'core.tap',
                toolResult: '✓ ok',
                // complete defaults to false
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('result.0')), findsNothing);
    });
  });
}
