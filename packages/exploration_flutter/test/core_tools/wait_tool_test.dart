import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core.wait rejects seconds <= 0 and > 5 as schema_violation',
      () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool wait =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'wait');
    for (final num bad in const <num>[0, -1, 5.0001, 6, 100]) {
      final ToolResult r = await wait.call(<String, Object?>{
        'seconds': bad,
      });
      expect(r.ok, isFalse, reason: 'seconds=$bad should be rejected');
      expect(r.error, contains('schema_violation'));
    }
    cap.dispose();
  });

  test('core.wait completes for an in-range duration', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool wait =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'wait');
    final Stopwatch sw = Stopwatch()..start();
    final ToolResult r =
        await wait.call(<String, Object?>{'seconds': 0.05});
    sw.stop();
    expect(r.ok, isTrue, reason: r.error);
    // 50ms target with comfortable upper bound.
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
    cap.dispose();
  });
}
