import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MyButton extends StatelessWidget {
  const MyButton({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

Element _root(WidgetTester tester) {
  final Element root = tester.binding.rootElement!;
  return root;
}

void main() {
  testWidgets('bare GestureDetector with onTap produces one warning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          onTap: () {},
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    final InteractiveSemanticsAuditor auditor = InteractiveSemanticsAuditor();
    final List<InteractiveSemanticsWarning> warnings = auditor.audit(
      _root(tester),
    );
    expect(warnings, hasLength(1));
    expect(warnings.first.widgetType, 'GestureDetector');
    expect(warnings.first.location, contains('GestureDetector'));
    expect(warnings.first.suggestedFixPointer, kExtensionGuideFixPointer);
  });

  testWidgets('GestureDetector wrapped in Semantics with label is ignored', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(
          label: 'tap target',
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    final InteractiveSemanticsAuditor auditor = InteractiveSemanticsAuditor();
    final List<InteractiveSemanticsWarning> warnings = auditor.audit(
      _root(tester),
    );
    expect(warnings, isEmpty);
  });

  testWidgets('bare InkWell with onTap produces one warning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: InkWell(
            onTap: () {},
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    final InteractiveSemanticsAuditor auditor = InteractiveSemanticsAuditor();
    final List<InteractiveSemanticsWarning> warnings = auditor.audit(
      _root(tester),
    );
    final Iterable<InteractiveSemanticsWarning> inkHits = warnings.where(
      (InteractiveSemanticsWarning w) => w.widgetType == 'InkWell',
    );
    expect(inkHits, hasLength(1));
  });

  testWidgets('extraInteractiveTypes flags custom widget without semantics', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: MyButton()),
    );
    final InteractiveSemanticsAuditor auditor = InteractiveSemanticsAuditor(
      extraInteractiveTypes: const <String>['MyButton'],
    );
    final List<InteractiveSemanticsWarning> warnings = auditor.audit(
      _root(tester),
    );
    expect(warnings, hasLength(1));
    expect(warnings.first.widgetType, 'MyButton');
  });
}
