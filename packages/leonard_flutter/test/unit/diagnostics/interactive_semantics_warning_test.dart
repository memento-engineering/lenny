import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson round-trips all three fields', () {
    final InteractiveSemanticsWarning w = InteractiveSemanticsWarning(
      widgetType: 'GestureDetector',
      location: 'GestureDetector ← Center ← MyHomePage',
      suggestedFixPointer: kExtensionGuideFixPointer,
    );
    expect(w.toJson(), <String, Object?>{
      'widget_type': 'GestureDetector',
      'location': 'GestureDetector ← Center ← MyHomePage',
      'suggested_fix_pointer': kExtensionGuideFixPointer,
    });
  });

  test('kExtensionGuideFixPointer matches the exact canonical message', () {
    expect(
      kExtensionGuideFixPointer,
      "These widgets won't be visible to the agent. Add semantics "
      'annotations, or write an extension that exposes them — see '
      'https://github.com/memento-engineering/lenny/blob/main/docs/extension_authoring_guide.md.',
    );
  });
}
