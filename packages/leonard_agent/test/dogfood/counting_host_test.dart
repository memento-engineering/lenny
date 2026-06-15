/// Unit tests for [CountingLoopHost].
library;

import 'package:leonard_agent/leonard_agent.dart' show LoopHost, Observation;
import 'package:leonard_agent/src/dogfood/counting_host.dart';
import 'package:leonard_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:test/test.dart';

class _FakeHost implements LoopHost {
  _FakeHost({this.throwOnAct = false});
  final bool throwOnAct;
  int observeCalls = 0;
  int actCalls = 0;
  int notifyCalls = 0;
  final List<String> disabled = <String>[];

  @override
  String get agentsMd => 'md';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async {
    observeCalls++;
    return Observation.empty();
  }

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    actCalls++;
    if (throwOnAct) throw StateError('boom');
    return <String, dynamic>{'tool': tool, 'args': args};
  }

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {
    notifyCalls++;
  }

  @override
  void disableExtension(String namespace, String reason) {
    disabled.add('$namespace:$reason');
  }

  @override
  List<ToolDescriptor> mergedTools() => const <ToolDescriptor>[];

  @override
  Set<String> activeExtensionNamespaces() => const <String>{};
}

void main() {
  group('CountingLoopHost', () {
    test('increments counter on successful executeAction', () async {
      final inner = _FakeHost();
      final host = CountingLoopHost(inner);
      expect(host.toolCallCount, 0);

      await host.executeAction('core.tap', <String, dynamic>{});
      await host.executeAction('core.tap', <String, dynamic>{});
      expect(host.toolCallCount, 2);
      expect(inner.actCalls, 2);
    });

    test('does NOT increment when executeAction throws', () async {
      final inner = _FakeHost(throwOnAct: true);
      final host = CountingLoopHost(inner);
      await expectLater(
        host.executeAction('core.tap', <String, dynamic>{}),
        throwsStateError,
      );
      expect(host.toolCallCount, 0);
    });

    test('forwards remaining LoopHost methods verbatim', () async {
      final inner = _FakeHost();
      final host = CountingLoopHost(inner);

      expect(host.goal, 'goal');
      expect(host.agentsMd, 'md');
      expect(host.mergedTools(), isEmpty);
      expect(host.activeExtensionNamespaces(), isEmpty);

      await host.observe();
      expect(inner.observeCalls, 1);

      await host.notifyExtensions(
        'core.tap',
        <String, dynamic>{},
        <String, dynamic>{},
      );
      expect(inner.notifyCalls, 1);

      host.disableExtension('router', 'flaky');
      expect(inner.disabled, <String>['router:flaky']);
    });
  });
}
