/// The scripted host is the measurement fixture — if it lies, the number the
/// harness reports is meaningless.
library;

import 'package:leonard_acp/leonard_acp.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  test('tapping the increment node advances the counter', () async {
    final ScriptedCounterHost host = ScriptedCounterHost(target: 3);
    expect(host.counter, 0);

    final Map<String, dynamic> r = await host.executeAction('core.tap', {
      'node_id': kIncrementNodeId,
    });

    expect(host.counter, 1);
    expect(r['counter'], 1);
  });

  test('tapping any other node does NOT advance the counter', () async {
    final ScriptedCounterHost host = ScriptedCounterHost();
    await host.executeAction('core.tap', {'node_id': kCounterNodeId});
    expect(host.counter, 0);
  });

  test('the observation reports the live counter value', () async {
    final ScriptedCounterHost host = ScriptedCounterHost();
    await host.executeAction('core.tap', {'node_id': kIncrementNodeId});

    final Observation obs = await host.observe();
    expect(obs.core.nodes[kCounterNodeId]!.label, 'Count: 1');
  });

  test('every node the tools can target exists in the observation', () async {
    final ScriptedCounterHost host = ScriptedCounterHost();
    final Observation obs = await host.observe();

    // ActionValidator's third pass rejects any node_id absent from the
    // observation — the fixture must not set that trap by accident.
    expect(obs.core.nodes.containsKey(kIncrementNodeId), isTrue);
    expect(obs.core.nodes.containsKey(kCounterNodeId), isTrue);
  });

  test('merged tools compose a valid ActionSchema', () {
    final ScriptedCounterHost host = ScriptedCounterHost();
    final ActionSchema schema = ActionSchema.fromToolList(host.mergedTools());

    final Map<String, dynamic> ok = schema.validate(
      '{"action":{"tool":"core.tap","args":{"node_id":$kIncrementNodeId}}}',
    );
    expect((ok['action']! as Map<String, dynamic>)['tool'], 'core.tap');

    expect(
      () => schema.validate('{"action":{"tool":"core.fly","args":{}}}'),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('the goal names the target so the agent can stop', () {
    expect(ScriptedCounterHost(target: 7).goal, contains('7'));
  });
}
