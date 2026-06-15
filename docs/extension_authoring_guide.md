# Extension Authoring Guide

> Companion to [`leonard_prd_v0.5.md`](./leonard_prd_v0.5.md). The PRD is canonical; this guide is the on-ramp.
> Stable URL: `docs/extension_authoring_guide.md`.

## 1. The extension contract

Every type below is exported from `package:leonard_flutter/contract.dart`. Authors should never need to reach into the package's private internals. Each subsection cites the matching PRD clause for canonical wording.

### 1.1 `LeonardExtension` (PRD §7.1)

The top-level interface. An extension owns a `namespace` (used to scope tool names and VM service extensions) and a list of `tools`. The host calls `initialize` once per session, then `observe`, `busyState`, and `onActionExecuted` over the session's lifetime, and finally `dispose`.

```dart
class HelloExtension implements LeonardExtension {
  @override final String namespace = 'hello';
  @override final List<LeonardTool> tools = const [];
  @override Future<void> initialize(ExtensionContext ctx) async {}
  @override Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override Future<BusyState> busyState() async => BusyState.idle;
  @override Future<void> onActionExecuted(ExecutedAction action) async {}
  @override Future<void> dispose() async {}
}
```

### 1.2 `LeonardTool` (PRD §7.1)

A single tool. The bare `name` is prefixed with the extension's namespace by the registry (`<namespace>.<name>`); never include a `.` yourself.

```dart
class NavigateToTool implements LeonardTool {
  @override final String name = 'navigate_to'; // host prefixes to `router.navigate_to`
  @override final String description = 'Pushes a named route onto the navigator.';
  @override final JsonSchema inputSchema = const JsonSchema({
    'type': 'object',
    'properties': {'route': {'type': 'string'}},
    'required': ['route'],
  });
  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final route = args['route'];
    if (route is! String) return const ToolResult(ok: false, error: 'route required');
    return const ToolResult(ok: true);
  }
}
```

### 1.3 `JsonSchema` (PRD §7.1)

An opaque holder for a JSON Schema fragment describing a tool's input. The host treats `raw` as a pass-through; expand it as the agent's model provider grows new capabilities without breaking older hosts.

```dart
const schema = JsonSchema({
  'type': 'object',
  'properties': {'name': {'type': 'string'}},
  'required': ['name'],
});
```

### 1.4 `ToolResult` (PRD §7.1)

The outcome of a tool invocation. `ok=true` may carry a `value`; `ok=false` should carry an `error` string. Extensions must not throw out of `call`; catch and return `ToolResult(ok: false, error: ...)` instead (see §5.4).

```dart
return const ToolResult(ok: true, value: {'pushed': 'home'});
// or
return const ToolResult(ok: false, error: 'route not registered');
```

### 1.5 `BusyState` (PRD §7.4)

Whether the extension reports the app as busy. Use `BusyState.idle` for "no contribution"; only return `isBusy: true` for extension-known async work the host cannot see (in-flight HTTP, extension-owned timers, etc.). Frame work and animations are already host-covered via `SchedulerBinding`.

```dart
@override
Future<BusyState> busyState() async {
  if (_inFlightRequests > 0) {
    return const BusyState(
      isBusy: true,
      reason: 'http requests in flight',
      estimatedDuration: Duration(seconds: 2),
    );
  }
  return BusyState.idle;
}
```

### 1.6 `ObservationContext` (PRD §7.3)

Read-only context passed to `observe`. Includes `turn` (monotonic per session) and `sinceLastAction` (wall-clock since the previous action). Use it to throttle expensive observations — for example, only walking the element tree on the first turn after a navigation.

```dart
@override
Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
  if (ctx.sinceLastAction < const Duration(milliseconds: 50)) return null;
  return {'turn': ctx.turn, 'route': _currentRoute};
}
```

### 1.7 `ExecutedAction` (PRD §7.3)

Record of a tool the harness just executed. Receive it via `onActionExecuted` to update internal counters, invalidate caches, or stage follow-up work for the next `observe` call. The `toolName` is fully-qualified (`<namespace>.<tool>`).

```dart
@override
Future<void> onActionExecuted(ExecutedAction action) async {
  if (action.toolName == 'router.navigate_to' && action.result.ok) {
    _staleRouteCache = true;
  }
}
```

### 1.8 `ExtensionContext` (PRD §7.5)

Per-extension context handed to `initialize`. Auto-namespaces VM service extensions under `ext.exploration.<namespace>.<suffix>` and gates frame callbacks through the host scheduler. Three registration methods:

- `registerErrorHandler(ErrorHandler)` — append to this extension's chained error handlers; return `true` to claim, `false` to defer.
- `registerExtension(String suffix, ExtensionHandler)` — register a VM service extension under this extension's namespace.
- `registerFrameCallback(FrameCallback)` — forwarded to `SchedulerBinding.addPostFrameCallback`.

```dart
@override
Future<void> initialize(ExtensionContext ctx) async {
  ctx.registerErrorHandler((d) {
    debugPrint('[${ctx.namespace}] ${d.exceptionAsString()}');
    return false; // let the next handler try
  });
  ctx.registerExtension('snapshot', (method, params) async {
    return developer.ServiceExtensionResponse.result('{"ok": true}');
  });
}
```


## 2. A complete hello-world extension

The block below is a complete extension. Copy it into a fresh package's `lib/`, depend on `package:leonard_flutter`, and `dart analyze` is clean. It exercises every method on the contract once: a namespace, one tool, an observation fragment that surfaces an extension-owned identifier, a busy-state hook, an action callback, an error handler, and a `dispose`.

```dart
import 'package:leonard_flutter/contract.dart';
import 'package:flutter/foundation.dart';

class HelloExtension implements LeonardExtension {
  @override final String namespace = 'hello';
  @override final List<LeonardTool> tools = [_GreetTool()];
  int _calls = 0;
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  @override
  Future<void> initialize(ExtensionContext c) async {
    c.registerErrorHandler((d) { debugPrint('[hello] $d'); return false; });
  }
  @override
  Future<Map<String, Object?>?> observe(ObservationContext c) async => {
    'session_id': _sessionId, // surfaced because tools accept it (§21 convention)
    'calls_so_far': _calls,
  };
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction a) async {
    if (a.toolName == 'hello.greet' && a.result.ok) _calls++;
  }
  @override
  Future<void> dispose() async {}
}

class _GreetTool implements LeonardTool {
  @override final String name = 'greet';
  @override final String description = 'Returns a greeting for the given name.';
  @override final JsonSchema inputSchema = const JsonSchema({
    'type': 'object',
    'properties': {'name': {'type': 'string'}, 'session_id': {'type': 'string'}},
    'required': ['name'],
  });
  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final n = args['name'];
    if (n is! String || n.isEmpty) return const ToolResult(ok: false, error: 'name required');
    return ToolResult(ok: true, value: 'hello, $n');
  }
}
```

Register it from your app entrypoint (PRD §7.6):

```dart
void main() {
  LeonardBinding.ensureInitialized(plugins: [HelloExtension()]);
  runApp(const MyApp());
}
```

The host installs the binding only in debug/profile; in release `ensureInitialized` is a no-op and returns `null`, so this call is safe to ship.

## 3. Reference extensions

The host repo ships three reference extensions as readable source. Each one is a worked example of one feature of the contract — action contribution, structured observation, and the busy-state hook. Until each extension's bead lands, the subsection below is a stub that names the package path so external authors can grep for it.

### 3.1 `leonard_router` (action contribution)

_Slotted in when [lenny-cx6.25] lands. Will demonstrate raw `Router`/`Navigator` integration and the `navigate_to` action shape._

### 3.2 `leonard_riverpod` (structured state observation)

_Slotted in when [lenny-cx6.26] lands. Will demonstrate provider-graph fragments and the `invalidate_provider` action._

### 3.3 `leonard_dio` (busy-state hook)

_Slotted in when [lenny-cx6.27] lands. Will demonstrate `busyState()` returning `isBusy=true` while requests are in flight._

## 4. Conventions

These are not enforced by the type system, but the host registry and most reviewers will reject deviations.

### 4.1 Namespace selection

A namespace must match `^[a-z][a-z0-9_]*$` and be unique within a session. The registry rejects duplicate registrations at `LeonardBinding.ensureInitialized` time (PRD §7.1, §7.8). Pick a short, package-aligned token (`router`, `riverpod`, `dio`); avoid generic words like `app` or `host`. The same token scopes both your tool names (`<namespace>.<tool>`) and your VM service extensions (`ext.exploration.<namespace>.<suffix>`).

### 4.2 Observation budget

Each extension contributes an observation fragment with a default budget of 1 KB serialized. The host truncates over-budget fragments and emits a warning; oversized contributions starve other extensions of attention from the agent's context window. Return `null` from `observe` when you have nothing relevant this turn — that is cheaper than returning an empty map and signals "no contribution" cleanly (PRD §7.3, §11.4).

### 4.3 When to report busy

Report `BusyState.isBusy=true` only for extension-known async work the host cannot see: an HTTP request you initiated, an extension-owned timer, an external IPC awaiting reply. Frame work, layout, animations, and post-frame settling are already covered by the host via `SchedulerBinding`; reporting busy for them is double-counting and slows the agent down (PRD §7.4, §9).

### 4.4 Surfacing extension-owned identifiers

If your tools accept an identifier (a session ID, a route name, a provider key) the agent has no way to discover, your observation fragment must include it. The §21 default is: every extension-owned identifier that appears in `inputSchema` should appear in the fragment. The `HelloExtension` `_sessionId` field in §2 is the worked example — `_GreetTool.inputSchema` accepts a `session_id`, so `observe` returns one.

## 5. Anti-patterns

Each of the four mistakes below is silent on the happy path and corrosive on the failure path. The registry's per-method 3-strikes auto-disable (cx6.3 step 4) catches repeated exceptions in `observe`/`busyState`/`onActionExecuted` and quietly drops the extension from subsequent dispatch — so the cost of a swallowed bug is your extension disappearing mid-session with no signal in the user's logs.

### 5.1 Don't subclass the binding

`LeonardBinding` extends `WidgetsFlutterBinding` and is incompatible with any other custom binding (`IntegrationTestWidgetsFlutterBinding`, Marionette, etc.). Subclassing or replacing it from an extension breaks the host's invariants and trips the `StateError` in `ensureInitialized`. If you need to coexist with another binding, use a reimplementation extension (§6.4) or accept that the two tools cannot share a process (PRD §7.5).

### 5.2 Don't hog frame callbacks

Frame callbacks registered through `ExtensionContext.registerFrameCallback` run on the host scheduler's post-frame phase. Long-running work (decoding, file IO, large element-tree walks) starves animation and observation. Schedule expensive work on a microtask or isolate and have the frame callback only enqueue it (PRD §7.5).

### 5.3 Don't return unbounded fragments

`observe` is called once per turn. Returning the entire provider graph, the full element tree, or every HTTP response body blows past the 1 KB default budget and either gets truncated mid-string (corrupting JSON) or starves siblings. Aggregate, count, summarise, and emit identifiers — let the agent pull detail through tools (PRD §7.3).

### 5.4 Don't swallow exceptions

Wrapping the body of `observe`/`busyState`/`onActionExecuted` in `try { ... } catch (_) {}` defeats the registry's auto-disable and hides real bugs. The contract is: throw out of these methods if something is genuinely wrong; the registry isolates the failure, increments the strike counter, and disables the offending method after three strikes. Inside `LeonardTool.call` the contract inverts — never throw; return `ToolResult(ok: false, error: ...)` (PRD §7.8).

## 6. Wrapping existing tools (the §20.2 taxonomy)

PRD §20.2 names four ways an existing tool can become an extension. Pick the lowest-effort category that fits your dependency graph; the higher categories accumulate maintenance cost.

### 6.1 Configuration extensions

A configuration extension instantiates an existing tool and tweaks a flag. The extension owns no logic of its own beyond the flip. Example: a logging extension that constructs a wrapped tool with `verbose: true` and re-exposes its surface. The extension's `tools` list forwards to the wrapped instance, and `dispose` tears it down.

```dart
class VerboseLoggerExtension implements LeonardExtension {
  @override final String namespace = 'verbose_logger';
  final WrappedLogger _logger = WrappedLogger(verbose: true);
  @override List<LeonardTool> get tools => _logger.tools;
  // ... initialize / observe / busyState / onActionExecuted / dispose forward.
}
```

### 6.2 Composition extensions

A composition extension instantiates the tool, wires interceptors, and emits observations from the seam. The reference `leonard_dio` extension (forward-reference: lenny-cx6.27) is the canonical case: it constructs `Dio`, attaches a counting interceptor, and reports busy while requests are in flight. The extension owns the interceptor; the wrapped tool stays unmodified.

```dart
class DioExtension implements LeonardExtension {
  final Dio _dio = Dio()..interceptors.add(_BusyInterceptor());
  // observation fragment emits `inflight_request_count`.
}
```

### 6.3 Subclass extensions

When the tool you wrap exposes its own `WidgetsBinding` or other framework hook that cannot be composed (PRD §20.1), subclass it and have the host binding extend the subclass. The Marionette case study is the example: `LeonardBinding extends MarionetteBinding extends WidgetsFlutterBinding`. This is contingent — the parent binding must be designed to accept subclassing (it must not be `final`, must expose hooks as protected methods, etc.). If the parent does not cooperate, fall back to §6.4.

```dart
// Sketch only; actual integration depends on Marionette accepting subclassing.
class LeonardBinding extends MarionetteBinding /* ... */ {}
```

### 6.4 Reimplementation extensions

When neither composition nor subclassing is possible, write an extension that reimplements the tool's primitives without sharing code. Example: `leonard_marionette_compat` would expose a Marionette-shaped surface to the agent without depending on Marionette source (PRD §20.1). This is the highest-cost option — the reimplementation drifts from upstream over time — and is appropriate only when integration is the alternative to having no support at all.

## 7. The `extension/exploration/config.yaml` manifest

An extension package SHOULD ship a manifest at `extension/exploration/config.yaml` describing how to instantiate its extension class:

```yaml
# extension/exploration/config.yaml
namespace: hello
class: HelloExtension
library: package:hello_leonard_extension/hello_leonard_extension.dart
constructor:
  positional: []
  named: {}
```

v1 host does not read this file. Adopting the convention now means well-behaved extension packages are auto-discoverable when v2 lands. A package shipping both `extension/mcp/config.yaml` and `extension/exploration/config.yaml` integrates with both coding-time agents (Dart MCP server) and runtime exploration (this project) from one place — the Packaged AI Assets posture (PRD §7.6).

## 8. Versioning posture

Per PRD §7.7, the contract guarantees:

- Adding a tool to `tools` is non-breaking. Existing agents ignore unknown tool names; new agents discover the addition through tool listing.
- Expanding an `observe` fragment with new fields is non-breaking. The host treats unknown fields as opaque pass-through (verified by the cx6.3 contract test `'observe fragment passes unknown fields through'`).
- Refining `busyState` heuristics is non-breaking. The shape stays `BusyState`; only the conditions under which `isBusy=true` is returned shift.

Extension authors should release as often as they want.

## 9. Custom-widget extensions

**Failure mode.** Apps built on a custom design system often expose sparse `Semantics` — interactive elements ship without labels, roles, or hints because the design system never wired them up. The agent's targetability degrades sharply: it can see the pixels but cannot name the widgets, so tools that take a target identifier have nothing to anchor on.

**Fix.** Write a custom-widget extension specific to the app's design system. Walk the element tree from `WidgetsBinding.instance.rootElement`, identify bespoke widgets by their runtime type (`is MyAppButton`, `is MyAppCard`), and contribute a structured fragment of `{type, key, label}` triples plus targeting tools that accept those keys. The extension owns the keys (it minted them) and surfaces them per §4.4, so the agent can target widgets the framework never knew were interactive.

**Diagnostic hook.** The host diagnostic from lenny-cx6.10 warns when interactive widgets ship without semantics; its warning text points users at this section. If you see that warning in a host's logs, the resolution is "ship a custom-widget extension" — not "patch the host."

```dart
import 'package:flutter/widgets.dart';
import 'package:leonard_flutter/contract.dart';

class MyAppCustomWidgetsExtension implements LeonardExtension {
  @override final String namespace = 'myapp_widgets';
  @override final List<LeonardTool> tools = const [];
  @override Future<void> initialize(ExtensionContext ctx) async {}
  @override Future<BusyState> busyState() async => BusyState.idle;
  @override Future<void> onActionExecuted(ExecutedAction a) async {}
  @override Future<void> dispose() async {}

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    final found = <Map<String, Object?>>[];
    void visit(Element e) {
      final w = e.widget;
      if (w.runtimeType.toString().startsWith('MyApp')) {
        found.add({'type': w.runtimeType.toString(), 'key': w.key?.toString()});
      }
      e.visitChildren(visit);
    }
    visit(root);
    return {'custom_widgets': found};
  }
}
```
