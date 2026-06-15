@TestOn('vm')
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/thinking/thinking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/stub_turn_events.dart';

// dart:io import-scan removed: redundant with tool/check_no_dart_io.sh which
// runs in CI and isn't sensitive to test cwd. Web-compat is asserted there.

void main() {
  testWidgets(
    '200 chars/sec synthetic stream appends without dropping deltas',
    (t) async {
      final bus = TurnEventBus();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ThinkingPanelFromStream(events: bus.stream)),
        ),
      );

      // 200 chars/sec * 60 seconds = 12,000 single-char deltas. We push
      // them in batches of 200 with a one-second simulated tick between
      // batches so the auto-scroll callback runs at a realistic rate.
      const total = 12000;
      const batch = 200;
      for (int i = 0; i < total; i += batch) {
        for (int j = 0; j < batch; j++) {
          bus.push(
            const TurnThinking(0, ThinkingDelta(text: 'x', isFinal: false)),
          );
        }
        await t.pump(const Duration(milliseconds: 1000));
      }
      await t.pumpAndSettle();

      final selectable = t.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, isNotNull);
      expect(selectable.data!.length, greaterThanOrEqualTo(total));

      await bus.close();
    },
  );
}
