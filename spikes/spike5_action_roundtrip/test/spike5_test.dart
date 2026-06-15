/// Spike 5 — A2UI action round-trip, setState flavor (genesis A5).
///
/// Surface emitted from the catalog carries an ACTION affordance; a
/// client-fired A2UI v0.9 action message routes back as an INTENT that is
/// hit-tested against the LIVE mounted tree — ENFORCED via perceived()
/// (invalidating exactly the target subtree) when valid, REJECTED with a
/// structured reason (tree untouched) when not — with last-write-wins
/// semantics for racing writes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/field.dart';
import 'package:spike5_action_roundtrip/action_router.dart';
import 'package:spike5_action_roundtrip/src/components.dart';
import 'package:spike5_action_roundtrip/src/generator.dart';
import 'package:spike5_action_roundtrip/surface.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// v1 surface: root panel with a label, button A, and a nested panel
/// holding button B (the "unrelated subtree" for rebuild isolation).
Map<String, Object?> v1Message() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'counters',
    'components': [
      {
        'id': 'root',
        'component': 'panel',
        'name': 'main',
        'children': ['lbl_title', 'btn_a', 'sub'],
      },
      {
        'id': 'lbl_title',
        'component': 'label',
        'name': 'Title',
        'value': 'Counters',
      },
      {'id': 'btn_a', 'component': 'button', 'label': 'Counter A'},
      {
        'id': 'sub',
        'component': 'panel',
        'name': 'side',
        'children': ['btn_b'],
      },
      {'id': 'btn_b', 'component': 'button', 'label': 'Counter B'},
    ],
  },
};

/// v2 whole-tree re-emission: REMOVES btn_a, updates the label value,
/// keeps everything else.
Map<String, Object?> v2Message() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'counters',
    'components': [
      {
        'id': 'root',
        'component': 'panel',
        'name': 'main',
        'children': ['lbl_title', 'sub'],
      },
      {
        'id': 'lbl_title',
        'component': 'label',
        'name': 'Title',
        'value': 'Counters v2',
      },
      {
        'id': 'sub',
        'component': 'panel',
        'name': 'side',
        'children': ['btn_b'],
      },
      {'id': 'btn_b', 'component': 'button', 'label': 'Counter B'},
    ],
  },
};

/// Client->server action message in the A2UI v0.9 `action` shape.
ActionMessage action(
  String name,
  String componentId, {
  Map<String, Object?> context = const {},
}) => ActionMessage.fromJson({
  'action': {
    'name': name,
    'surfaceId': 'counters',
    'sourceComponentId': componentId,
    'timestamp': '2026-06-11T12:00:00Z',
    'context': context,
  },
});

CounterButtonState stateOf(Surface surface, String id) =>
    (surface.findById(id)! as StatefulElement).state as CounterButtonState;

/// The rendered projection of a button: the Field its builder emitted.
String renderedValue(Surface surface, String id) =>
    ((surface.findById(id)! as StatefulElement).child!.perception as Field)
        .value;

String packageRoot() {
  // Resolves to .../spike5_action_roundtrip/lib/ — parent is the package root.
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:spike5_action_roundtrip/'),
  );
  return Directory.fromUri(libUri!).parent.path;
}

void main() {
  late Surface surface;
  late ActionRouter router;

  setUp(() {
    buttonBuildCounts.clear();
    surface = Surface.mount(v1Message());
    router = ActionRouter(surface);
  });

  tearDown(() {
    surface.owner.dispose();
  });

  test('(a) emitted tool schema declares the action affordance on the '
      'button type — an LLM can discover it', () {
    final schemaText = File(
      '${packageRoot()}/lib/src/generated/tool_schema.g.json',
    ).readAsStringSync();
    final schema = (jsonDecode(schemaText) as Map).cast<String, Object?>();
    final oneOf =
        ((((schema['properties'] as Map)['updateComponents']
                            as Map)['properties']
                        as Map)['components']
                    as Map)['items']
            as Map;
    final variants = (oneOf['oneOf'] as List).cast<Map<String, Object?>>();
    final byType = {
      for (final v in variants)
        ((v['properties'] as Map)['component'] as Map)['const'] as String: v,
    };

    // Structured affordance declaration on the button variant.
    final button = byType['button']!;
    final xActions = (button['x-actions'] as Map).cast<String, Object?>();
    expect(xActions.keys, unorderedEquals(['press', 'set']));
    expect(
      ((xActions['press'] as Map)['description'] as String),
      contains('Increment'),
    );
    expect(
      ((xActions['set'] as Map)['description'] as String),
      contains('Last write wins'),
    );
    // Prose discovery path: the variant description names the actions and
    // how to address the component.
    final description = button['description'] as String;
    expect(description, contains('AFFORDS CLIENT ACTIONS'));
    expect(description, contains('"press"'));
    expect(description, contains('sourceComponentId'));

    // Non-actionable types declare nothing.
    expect(byType['label']!.containsKey('x-actions'), isFalse);
    expect(byType['panel']!.containsKey('x-actions'), isFalse);
    expect(byType['label']!['description'], isNot(contains('AFFORDS')));
  });

  test('generator-in-sync: committed .g files match in-memory regeneration '
      'from schema/catalog.json (determinism + provenance)', () {
    final root = packageRoot();
    final outputs = generateSpike5(
      File('$root/schema/catalog.json').readAsStringSync(),
    );
    expect(
      File('$root/lib/src/generated/registry.g.dart').readAsStringSync(),
      outputs.registryDart,
    );
    expect(
      File('$root/lib/src/generated/tool_schema.g.json').readAsStringSync(),
      outputs.toolSchemaJson,
    );
    expect(
      File('$root/lib/src/generated/actions.g.dart').readAsStringSync(),
      outputs.actionsDart,
    );
  });

  test('(b) valid action -> Applied: enforced via perceived(), exactly the '
      'target subtree rebuilt, harvest drained', () {
    // Mount built each button exactly once.
    expect(buttonBuildCounts, {'btn_a': 1, 'btn_b': 1});

    final result = router.route(action('press', 'btn_a'));

    expect(result, isA<Applied>());
    final applied = result as Applied;
    expect(applied.componentId, 'btn_a');
    expect(applied.action, 'press');
    expect(applied.change, {
      'count': {'from': 0, 'to': 1},
    });

    // ENFORCED immediately (perceived() mutates synchronously) ...
    expect(stateOf(surface, 'btn_a').count, 1);
    // ... with the rebuild pending in the owner's dirty set.
    expect(surface.hasPendingHarvest, isTrue);

    surface.flush();

    // Exactly the target subtree rebuilt: btn_a's builder ran again,
    // unrelated btn_b's builder did NOT.
    expect(buttonBuildCounts, {'btn_a': 2, 'btn_b': 1});
    // Rendered projection reflects the new count.
    expect(renderedValue(surface, 'btn_a'), '1');
    expect(renderedValue(surface, 'btn_b'), '0');

    // flushHarvest drained: nothing pending, a second flush is a no-op.
    expect(surface.hasPendingHarvest, isFalse);
    surface.flush();
    expect(buttonBuildCounts, {'btn_a': 2, 'btn_b': 1});
  });

  test('(b2) onNeedsHarvest microtask auto-flush drains without a manual '
      'flush call', () async {
    router.route(action('press', 'btn_a'));
    expect(surface.hasPendingHarvest, isTrue);
    expect(buttonBuildCounts['btn_a'], 1); // not yet rebuilt

    await Future<void>.delayed(Duration.zero); // let microtasks run

    expect(surface.hasPendingHarvest, isFalse);
    expect(buttonBuildCounts['btn_a'], 2);
    expect(renderedValue(surface, 'btn_a'), '1');
  });

  test('(c) unknown componentId -> Rejection(unknownComponent), zero '
      'rebuilds, tree byte-for-byte untouched', () {
    final before = surface.dumpLiveTree();

    final result = router.route(action('press', 'btn_zzz'));

    expect(result, isA<Rejection>());
    final rejection = result as Rejection;
    expect(rejection.reason, RejectionReason.unknownComponent);
    expect(rejection.componentId, 'btn_zzz');
    expect(rejection.detail, contains('never existed'));

    expect(surface.dumpLiveTree(), before);
    expect(buttonBuildCounts, {'btn_a': 1, 'btn_b': 1});
    expect(stateOf(surface, 'btn_a').count, 0);
    expect(surface.hasPendingHarvest, isFalse);
  });

  test('(d) undeclared action name on a real component -> '
      'Rejection(undeclaredAction), zero rebuilds', () {
    final before = surface.dumpLiveTree();

    // A real, mounted button — but "detonate" is not in its catalog type's
    // declared actions.
    final r1 = router.route(action('detonate', 'btn_a'));
    expect(r1, isA<Rejection>());
    expect((r1 as Rejection).reason, RejectionReason.undeclaredAction);
    expect(r1.detail, contains('press'));
    expect(r1.detail, contains('detonate'));

    // A real, mounted label — its catalog type declares NO actions at all,
    // so even a name valid for buttons is rejected.
    final r2 = router.route(action('press', 'lbl_title'));
    expect(r2, isA<Rejection>());
    expect((r2 as Rejection).reason, RejectionReason.undeclaredAction);
    expect(r2.detail, contains('"label"'));

    expect(surface.dumpLiveTree(), before);
    expect(buttonBuildCounts, {'btn_a': 1, 'btn_b': 1});
    expect(surface.hasPendingHarvest, isFalse);
  });

  test('(d2) bad payload on a declared action -> Rejection(badPayload), '
      'no mutation', () {
    final before = surface.dumpLiveTree();

    final result = router.route(
      action('set', 'btn_a', context: {'value': 'nine'}),
    );

    expect(result, isA<Rejection>());
    expect((result as Rejection).reason, RejectionReason.badPayload);
    expect(result.detail, contains('context.value'));

    expect(surface.dumpLiveTree(), before);
    expect(stateOf(surface, 'btn_a').count, 0);
    expect(buttonBuildCounts, {'btn_a': 1, 'btn_b': 1});
    expect(surface.hasPendingHarvest, isFalse);
  });

  test('(e) STALENESS: v2 re-emission removes the button; the previously '
      'valid action -> Rejection(staleUnmounted) — the projection moved '
      'under the actor', () {
    // The action is valid against v1 — prove it.
    final r1 = router.route(action('press', 'btn_a'));
    expect(r1, isA<Applied>());
    surface.flush();
    expect(stateOf(surface, 'btn_a').count, 1);
    expect(buttonBuildCounts, {'btn_a': 2, 'btn_b': 1});

    final btnAElement = surface.findById('btn_a')!;
    final btnBElement = surface.findById('btn_b')!;
    final lblElement = surface.findById('lbl_title')!;

    // Whole-tree v2 re-emission through the SAME wire path; keyed reconcile
    // patches in place.
    surface.applyUpdate(v2Message());

    // btn_a is gone from the live tree (its element unmounted) ...
    expect(btnAElement.mounted, isFalse);
    expect(surface.findById('btn_a'), isNull);
    // ... while survivors kept their element identity and LIVE STATE.
    expect(identical(surface.findById('btn_b'), btnBElement), isTrue);
    expect(identical(surface.findById('lbl_title'), lblElement), isTrue);
    expect((lblElement.perception as Field).value, 'Counters v2');
    expect(stateOf(surface, 'btn_b').count, 0);
    // Reconcile itself ran no builders.
    expect(buttonBuildCounts, {'btn_a': 2, 'btn_b': 1});

    // The agent-async-gap moment: the actor fires the action that WAS valid.
    final before = surface.dumpLiveTree();
    final r2 = router.route(action('press', 'btn_a'));

    expect(r2, isA<Rejection>());
    final rejection = r2 as Rejection;
    expect(rejection.reason, RejectionReason.staleUnmounted);
    expect(rejection.detail, contains('no longer mounted'));

    // Distinguishable from unknownComponent: btn_a IS in everSeenIds.
    expect(surface.everSeenIds, contains('btn_a'));

    expect(surface.dumpLiveTree(), before);
    expect(buttonBuildCounts, {'btn_a': 2, 'btn_b': 1});
    expect(surface.hasPendingHarvest, isFalse);
  });

  test('(f) LAST-WRITE-WINS: racing writes to the same value — final state '
      'equals the LAST write, both Applied, no merge', () {
    // Race 1: two sets back-to-back BEFORE any flush.
    final r1 = router.route(action('set', 'btn_a', context: {'value': 5}));
    final r2 = router.route(action('set', 'btn_a', context: {'value': 9}));

    expect(r1, isA<Applied>());
    expect(r2, isA<Applied>());
    // Writes applied synchronously, in arrival order — the second saw the
    // first's result (from: 5), then overwrote it. No merge.
    expect((r1 as Applied).change, {
      'count': {'from': 0, 'to': 5},
    });
    expect((r2 as Applied).change, {
      'count': {'from': 5, 'to': 9},
    });
    expect(stateOf(surface, 'btn_a').count, 9); // LAST write

    surface.flush();
    // Two writes, ONE rebuild: the dirty set coalesced them (mount build +
    // this one = 2).
    expect(buttonBuildCounts['btn_a'], 2);
    expect(renderedValue(surface, 'btn_a'), '9');

    // Race 2: a flush BETWEEN the writes changes nothing about the outcome.
    final r3 = router.route(action('set', 'btn_a', context: {'value': 3}));
    surface.flush();
    final r4 = router.route(action('set', 'btn_a', context: {'value': 7}));
    surface.flush();

    expect(r3, isA<Applied>());
    expect(r4, isA<Applied>());
    expect(stateOf(surface, 'btn_a').count, 7); // LAST write again
    expect(renderedValue(surface, 'btn_a'), '7');
    expect(buttonBuildCounts['btn_a'], 4); // one rebuild per flushed write

    // The unrelated subtree never rebuilt through any of it.
    expect(buttonBuildCounts['btn_b'], 1);
  });
}
