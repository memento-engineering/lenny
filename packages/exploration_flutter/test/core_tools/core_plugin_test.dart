import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exposes namespace "core" and 10 tools in stable order', () {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    expect(plugin.namespace, 'core');
    expect(
      plugin.tools.map((ExplorationTool t) => t.name).toList(),
      <String>[
        'tap',
        'long_press',
        'enter_text',
        'scroll',
        'scroll_until_visible',
        'gesture',
        'system_back',
        'wait',
        'inspect_widget',
        'done',
      ],
    );
    cap.dispose();
  });

  test('tools list is cached across calls', () {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final List<ExplorationTool> a = plugin.tools;
    final List<ExplorationTool> b = plugin.tools;
    expect(identical(a, b), isTrue);
    cap.dispose();
  });

  test('PluginRegistry rejects user plugin that claims namespace "core"',
      () {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin host = CorePlugin(semantics: cap);
    final PluginRegistry r =
        PluginRegistry(scheduler: SchedulerBinding.instance);
    r.register(host);
    expect(
      () => r.register(_FakeUserPlugin('core')),
      throwsStateError,
      reason: 'duplicate-namespace check reserves "core" for the host',
    );
    cap.dispose();
  });

  test('terminated flag flips after DoneTool runs', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    expect(plugin.terminated, isFalse);
    final ExplorationTool done =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'done');
    final ToolResult r = await done.call(<String, Object?>{
      'reason': 'session over',
    });
    expect(r.ok, isTrue);
    expect(r.value, <String, Object?>{
      'type': 'done',
      'reason': 'session over',
    });
    expect(plugin.terminated, isTrue);
    cap.dispose();
  });

  test('after done, action tools return session_terminated', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool done =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'done');
    await done.call(<String, Object?>{'reason': 'bye'});
    final ExplorationTool tap =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'tap');
    final ToolResult r = await tap.call(<String, Object?>{'node_id': 1});
    expect(r.ok, isFalse);
    expect(r.error, contains('session_terminated'));
    cap.dispose();
  });
}

class _FakeUserPlugin extends ExplorationPlugin {
  _FakeUserPlugin(this.namespace);
  @override
  final String namespace;
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}
