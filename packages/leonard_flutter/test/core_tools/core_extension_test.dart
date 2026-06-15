import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exposes namespace "core" and 10 tools in stable order', () {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    expect(plugin.namespace, 'core');
    expect(plugin.tools.map((LeonardTool t) => t.name).toList(), <String>[
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
    ]);
    cap.dispose();
  });

  test('tools list is cached across calls', () {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final List<LeonardTool> a = plugin.tools;
    final List<LeonardTool> b = plugin.tools;
    expect(identical(a, b), isTrue);
    cap.dispose();
  });

  test(
    'ExtensionRegistry rejects user plugin that claims namespace "core"',
    () {
      final SemanticsCapture cap = SemanticsCapture();
      final CoreExtension host = CoreExtension(semantics: cap);
      final ExtensionRegistry r = ExtensionRegistry(
        scheduler: SchedulerBinding.instance,
      );
      r.register(host);
      expect(
        () => r.register(_FakeUserExtension('core')),
        throwsStateError,
        reason: 'duplicate-namespace check reserves "core" for the host',
      );
      cap.dispose();
    },
  );

  test('terminated flag flips after DoneTool runs', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    expect(plugin.terminated, isFalse);
    final LeonardTool done = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'done',
    );
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
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool done = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'done',
    );
    await done.call(<String, Object?>{'reason': 'bye'});
    final LeonardTool tap = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'tap',
    );
    final ToolResult r = await tap.call(<String, Object?>{'node_id': 1});
    expect(r.ok, isFalse);
    expect(r.error, contains('session_terminated'));
    cap.dispose();
  });
}

class _FakeUserExtension extends LeonardExtension {
  _FakeUserExtension(this.namespace);
  @override
  final String namespace;
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}
