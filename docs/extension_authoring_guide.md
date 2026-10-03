# Leonard extension authoring guide

Leonard extensions contribute tools, busy-state signals, and optionally one
structured observation fragment. The same `leonard_contract` API runs in the
pure-Dart `ExplorationHost` and Flutter's `LeonardBinding`.

## The extension contract

Every extension implements `LeonardExtension`. An observing extension also
mixes in `PerceptionExtension`:

```dart
import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';

class CounterExtension extends LeonardExtension with PerceptionExtension {
  int _count = 0;

  @override
  String get namespace => 'counter';

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext context) async {}

  @override
  Component buildPerception() => CounterPerception(_count);

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class CounterPerception extends StatelessPerception {
  const CounterPerception(this.count, {super.key});

  final int count;

  @override
  Component build(PerceptionContext context) => Node(
    'counter',
    children: <Component>[Field('count', count)],
  );
}
```

`buildPerception()` is synchronous by contract. The host mounts the returned
`Component`, builds it, and serializes the root beneath
`extensions.<namespace>`.

## Pull-free perception

Build is a pure read. It must not write state, perform I/O, execute effects, or
start asynchronous work. Track asynchronous sources out of band and cache their
latest snapshot:

```dart
class ProcessExtension extends LeonardExtension with PerceptionExtension {
  StreamSubscription<ProcessSnapshot>? _subscription;
  ProcessSnapshot? _latest;

  @override
  Future<void> initialize(ExtensionContext context) async {
    _subscription = snapshots.listen((snapshot) => _latest = snapshot);
  }

  @override
  bool isPerceptionIdle() => _latest == null;

  @override
  Component buildPerception() => ProcessPerception(_latest!);

  @override
  Future<void> dispose() async => _subscription?.cancel();

  // namespace, tools, busyState, and onActionExecuted omitted.
}
```

Use the observation hooks for distinct responsibilities:

- `initialize()` starts watchers, subscriptions, and polling loops.
- `prepareForObservation()` synchronously publishes already-buffered changes
  immediately before the idle check and build. It is the only pre-build
  side-effect seam.
- `isPerceptionIdle()` suppresses the namespace when there is no useful
  fragment.
- `buildPerception()` synchronously reads the current in-memory snapshot.

The Riverpod extension uses `prepareForObservation()` to drain pending observer
changes. The tmux and native extensions update their cached snapshots from
watchers started by `initialize()`. None of them gathers during build.

## Tools and busy state

A tool name is a bare token. The host prefixes it with the extension namespace:

```dart
class RefreshTool extends LeonardTool {
  const RefreshTool(this.refresh);

  final Future<void> Function() refresh;

  @override
  String get name => 'refresh';

  @override
  String get description => 'Refresh the cached external state.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    try {
      await refresh();
      return const ToolResult(ok: true);
    } on Object catch (error) {
      return ToolResult(ok: false, error: '$error');
    }
  }
}
```

Return `BusyState(isBusy: true, ...)` only for extension-owned asynchronous work
the host cannot see. Flutter frames, layout, animations, and scheduler work are
already tracked by the host.

If a tool accepts an extension-owned identifier, include that identifier in the
perception fragment so the agent can discover it. Keep fragments bounded;
Leonard applies per-extension byte budgets after serialization.

## Flutter imports

Flutter and Genesis both define `Element` and `BuildContext`. Prefix Genesis in
mixed files so framework types remain unambiguous:

```dart
import 'package:flutter/widgets.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;

class FlutterAwarePerception extends genesis.StatelessPerception {
  const FlutterAwarePerception(this.flutterElement);

  final Element flutterElement;

  @override
  genesis.Component build(genesis.PerceptionContext context) => genesis.Node(
    'flutter_aware',
    children: <genesis.Component>[
      genesis.Field('widget', flutterElement.widget.runtimeType.toString()),
    ],
  );
}
```

Do not hide a collision by accidentally retargeting to Flutter's tree classes.
Genesis `Element` is a mounted component; Flutter `Element` is a mounted widget.

## Host registration

Pure Dart:

```dart
final host = ExplorationHost(extensions: <LeonardExtension>[
  CounterExtension(),
]);
await host.install();
```

Flutter:

```dart
void main() {
  LeonardBinding.ensureInitialized(
    extensions: <LeonardExtension>[CounterExtension()],
  );
  runApp(const App());
}
```

Runnable examples exercise both hosts:

- [`packages/leonard_host/example/canonical_perception_extension.dart`](../packages/leonard_host/example/canonical_perception_extension.dart)
- [`packages/leonard_flutter/example/diagnostic_fixture/lib/main.dart`](../packages/leonard_flutter/example/diagnostic_fixture/lib/main.dart)

## Compatibility

Genesis 0.4 keeps deprecated identity-preserving aliases for the retired tree
vocabulary. An existing extension whose override still returns `Seed` remains
compatible with `PerceptionExtension.buildPerception() -> Component`. New code
should use `Component`, `Element`, `BuildContext`, and `BuildOwner`; alias
removal will be a separate migration after consumers have moved.

The migration table and dependency floors are in
[`migrations/genesis-component-api.md`](migrations/genesis-component-api.md).

## Authoring conventions

Choose a short package-aligned namespace matching `^[a-z][a-z0-9_]*$`. The
registry rejects duplicates. The same token scopes tools
(`<namespace>.<tool>`), VM-service extensions
(`ext.leonard.<namespace>.<suffix>`), and the observation fragment.

The host treats `JsonSchema.raw` as an opaque JSON Schema document. Validate
arguments inside `LeonardTool.call`, return structured errors for expected bad
input, and keep tool names free of dots because the registry adds the namespace.

Each extension receives a bounded serialized fragment. Aggregate large state,
omit irrelevant payloads, and expose tools for detail instead of returning an
unbounded tree. Use `isPerceptionIdle()` when the namespace has nothing useful
to contribute.

`onActionExecuted()` receives the fully qualified tool name after any tool
runs. Use it to invalidate caches or stage watcher work, not to perform hidden
work during the next build.

## Reference extensions

The repository's extensions are worked examples of the contract:

- `leonard_router` projects a synchronous route snapshot and contributes the
  `router.navigate` tool.
- `leonard_riverpod` observes provider changes out of band and drains pending
  records in `prepareForObservation()`.
- `leonard_dio` tracks requests through an interceptor and reports busy while
  requests are in flight.
- `leonard_tmux` and `leonard_native` watch external processes and cache their
  latest snapshots before build.

## Anti-patterns

Do not subclass or replace `LeonardBinding` from an extension. The binding owns
Flutter's binding slot and composes extensions through registration.

Do not perform file, network, process, platform, or widget-tree traversal from
`build()` or `buildPerception()`. Move it to a watcher, listener, frame hook, or
tool action and publish an immutable snapshot for build to read.

Do not swallow unexpected observation or busy-state failures. Hosts isolate a
failing extension and log the failure. Silently converting every exception to
an empty fragment hides broken state and makes the extension disappear without
evidence.

Do not return full response bodies, provider graphs, accessibility documents,
or element trees by default. Prefer stable identifiers and compact summaries.

## Packaged extension metadata

An extension package may ship `extension/exploration/config.yaml` so future
hosts can discover its constructor without package-specific code:

```yaml
namespace: counter
class: CounterExtension
library: package:counter_leonard/counter_leonard.dart
constructor:
  positional: []
  named: {}
```

The version-1 host does not read this file yet. It is a packaging convention,
not a second registration API.

## Versioning posture

Adding a tool or an observation field is non-breaking because clients discover
tools through the handshake and treat unknown fragment fields opaquely.
Refining busy-state heuristics is also non-breaking while the `BusyState` shape
is stable. Changing a tool schema, removing a field, or changing a persisted or
wire key requires an explicit compatibility decision.

## Custom-widget extensions

Apps with sparse Flutter semantics can add a design-system-specific extension.
Observe bespoke Flutter widgets from an out-of-band tree watcher or frame hook,
cache compact `{type, key, label}` records, and expose those cached records from
a synchronous Genesis component. If a tool accepts a key minted by the
extension, surface that key in the fragment so the agent can discover it.

Keep Flutter's `Element` for the widget-tree walk and Genesis's
`genesis.Element` for the mounted perception tree. The build method reads only
the cached records; it does not traverse `WidgetsBinding.instance.rootElement`.

## Failure behavior

Hosts isolate observation failures per extension. Throwing from one extension's
build omits that fragment without aborting its siblings. Tool calls should catch
expected operational errors and return `ToolResult(ok: false, error: ...)`.
Always release subscriptions, clients, and other lifecycle-owned resources from
`dispose()`.
