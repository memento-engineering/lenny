import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core.done returns a structured terminal record', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool d =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'done');
    final ToolResult r =
        await d.call(<String, Object?>{'reason': 'all done'});
    expect(r.ok, isTrue, reason: r.error);
    expect(r.value, <String, Object?>{
      'type': 'done',
      'reason': 'all done',
    });
    expect(plugin.terminated, isTrue);
    cap.dispose();
  });

  test('core.done schema_violation when reason missing or too long',
      () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool d =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'done');
    final ToolResult miss = await d.call(const <String, Object?>{});
    expect(miss.ok, isFalse);
    expect(miss.error, contains('schema_violation'));
    final ToolResult long = await d.call(<String, Object?>{
      'reason': 'x' * 1024,
    });
    expect(long.ok, isFalse);
    expect(long.error, contains('schema_violation'));
    cap.dispose();
  });
}
