<p align="center">
  <img src="assets/lenny-icon-notext-256.png" alt="Leonard" width="160" height="160" />
</p>

<h1 align="center">Leonard</h1>

<p align="center">
  <strong>An agent that drives a real Flutter app — and knows when it's done reacting.</strong>
</p>

<p align="center">
  <img alt="status: proof of concept" src="https://img.shields.io/badge/status-proof%20of%20concept-f7c873" />
  <img alt="Flutter: debug mode" src="https://img.shields.io/badge/Flutter-3.41%2B-7aa2f7" />
  <img alt="Dart 3.11+" src="https://img.shields.io/badge/Dart-3.11%2B-6ee7b7" />
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-8a93a8" />
</p>

---

Leonard is an agent harness for running Flutter apps in debug mode. It taps, types,
scrolls, and looks — the way a person would — but it always waits for the frame to
settle first, and lets the app's own libraries report what's going on. The result
is **one trustworthy observation per turn**.

## The bet: wire an LLM straight into a running app

Leonard set out to answer one question: can you connect an LLM directly to a live
Flutter app — over the Dart VM service — and have it perceive the app's real state and
drive itself through it, turn after turn? It can.

The hard part is perception. A UI agent is only as good as its observation, and the
classic failure is acting _too early_ — reading the screen mid-animation,
mid-navigation, or mid-load, then acting on a snapshot that's already stale.

Flutter makes this tractable in a way most UIs don't:

- **Frame lifecycle.** Flutter's scheduler knows when work is pending and when a frame
  has committed — so _"is the app still settling?"_ has a real answer.
- **Semantics tree.** The screen-reader view of the UI gives interactable elements at a
  clean level of abstraction, not raw pixels.
- **VM-service hook.** A debug-mode app exposes a service the harness drives over the
  wire — observe, then act.

Put together: **observe a settled, structured snapshot; then act.** One trustworthy
observation per turn.

## How it works

The host is a small, opinion-free core — literally a custom `WidgetsBinding`. It claims
the framework's lifecycle slot in `main()`, registers a handful of VM-service
extensions, and otherwise gets out of the way. Outside debug/profile mode it doesn't
install at all.

Everything app-specific lives in **extensions** that ship _in your app_ — each contributes
some mix of extra **tools** (e.g. `router.navigate`), **observation fragments** (the
current route stack, which providers are loading), and **lifecycle hooks**. The core
stays tiny and policy-free; extensions know about your router, your state, your network
client.

```mermaid
graph TB
    subgraph dev["Your machine"]
        cli["leonard_cli<br/>headless / CI"]
        dt["DevTools panel<br/>Prompt · Thinking · Timeline"]
    end
    subgraph harness["leonard_agent — the loop"]
        loop["perceive → decide → validate → act<br/>+ stability policy + trajectory log"]
    end
    subgraph app["Your Flutter app (debug mode)"]
        binding["LeonardBinding<br/>custom WidgetsBinding = the host"]
        extensions["Extensions live here:<br/>router · riverpod · dio · yours"]
        binding --- extensions
    end
    cli --> loop
    dt --> loop
    loop -->|decide| models["Model:<br/>claude · openai · qwen-mlx"]
    loop <-->|"VM service:<br/>getStableObservation / executeAction"| binding
```

Every turn is the same shape:

1. **Stabilize** — wait until the framework _and_ every extension agree the app is done reacting.
2. **Observe** — capture one structured snapshot: semantics tree, route stack, errors, extension fragments.
3. **Decide** — a mechanical diff vs. the last turn plus the model's running summary → the model picks a tool.
4. **Validate** — reject impossible or malformed tool calls _before_ they hit the live app, so a bad call costs a re-prompt, not a turn.
5. **Act** — run the tool (core or extension) and append the turn to the trajectory log.

For the full, illustrated tour, read [`docs/how-leonard-works.md`](docs/how-leonard-works.md).

> Okay, so what am I doing? Oh, I'm chasing this guy. No, he's chasing me.
>
> — [Leonard Shelby](https://duckduckgo.com/?q=memento)

## Built on genesis

Leonard's perception layer is built on [**genesis**](https://github.com/memento-engineering/genesis) —
an open (BSD-3) toolkit for reconcilable trees and runtime perception:

- [**`genesis_tree`**](https://pub.dev/packages/genesis_tree) — the reconcilable tree spine
  (`Seed` / `Branch` / `TreeOwner`) that Leonard's observation tree is built on.
- [**`genesis_perception`**](https://pub.dev/packages/genesis_perception) — the measurement domain
  over that tree; every `build() → Perception` observation is a genesis perception tree.

## Packages

This is a Melos monorepo. The harness is frontend- and framework-agnostic; the host and
extensions are where Flutter specifics live.

| Package                                         | What it is                                                                                                                               |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [`leonard_agent`](packages/leonard_agent)       | The harness loop — web-compatible, frontend-agnostic. Stability policy, action validation, trajectory log, and the model providers.      |
| [`leonard_flutter`](packages/leonard_flutter)   | The host: a custom `WidgetsBinding` that claims the lifecycle slot in `main()` and exposes the VM-service extensions the harness drives. |
| [`leonard_native`](packages/leonard_native)     | The native channel — perceives and drives UI **outside** the Flutter engine via the OS accessibility tree (iOS XCUITest over Appium), so the harness can drive the real Auth0 hosted web-login and resume on Flutter. Pairs with multi-host attach. |
| [`leonard_cli`](packages/leonard_cli)           | Headless frontend — connects to a running app's VM service and streams a trajectory to disk.                                             |
| [`leonard_devtools`](packages/leonard_devtools) | In-IDE DevTools extension — the same loop in a panel, with live **Prompt**, **Thinking**, and **Timeline** views.                        |
| [`leonard_router`](packages/leonard_router)     | Reference extension — route-stack observation and a `router.navigate` tool.                                                              |
| [`leonard_riverpod`](packages/leonard_riverpod) | Reference extension — reports which providers are loading.                                                                               |
| [`leonard_dio`](packages/leonard_dio)           | Reference extension — reports (and can cancel) in-flight HTTP requests.                                                                  |

## Getting started

> **Prerequisites:** the [Flutter SDK](https://docs.flutter.dev/get-started/install)
> (Dart 3.11+, Flutter 3.41+). Leonard runs against apps in **debug or profile mode** —
> it relies on VM-service extensions that don't exist in release builds.

### 1. Install the host in your app

The minimal integration installs the binding and runs your app unchanged:

```dart
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  // Installs the host in debug/profile mode; a no-op in release.
  LeonardBinding.ensureInitialized(extensions: const <LeonardExtension>[]);
  runApp(const MyApp());
}
```

To teach the agent about your router, state, and network client, add reference extensions
(or your own). See [`example/sample_app`](packages/leonard_flutter/example/sample_app)
for a full `go_router` + Riverpod + Dio wiring.

### 2. Run your app and grab the VM-service URI

```sh
flutter run --debug
# Flutter prints: "A Dart VM Service ... is available at: ws://127.0.0.1:54321/abc=/ws"
```

### 3. Drive it

Headless, via the CLI:

```sh
export ANTHROPIC_API_KEY=sk-ant-…
dart run leonard_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings and enable dark mode"
```

…or interactively: open Flutter DevTools for the running app and pick the **Leonard**
tab (provided by `leonard_devtools`) to drive the same loop and watch the model think
live.

### Model backends

| `--model`            | Backend                                                                                       | Required env                                      |
| -------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `claude` _(default)_ | Anthropic                                                                                     | `ANTHROPIC_API_KEY`                               |
| `openai`             | OpenAI                                                                                        | `OPENAI_API_KEY`                                  |
| `qwen-mlx`           | local Qwen MoE via [swift-infer](packages/leonard_cli/README.md#swift-infer-gateway-qwen-mlx) | `SWIFT_INFER_ENDPOINT`, `SWIFT_INFER_AGENT_TOKEN` |

## Write an extension

An extension is a small Dart class that lives in _your_ app's `pubspec.yaml`, not in the
harness. It can declare tools, contribute an observation fragment in its library's own
native shape, and gate the stability check. The host namespaces every extension's tools
(`router.*`, `riverpod.*`, `dio.*`), budgets their output, and orders their hooks.

See the [extension authoring guide](docs/extension_authoring_guide.md), and the three
reference extensions above for working examples.

## Build & test

Install [Melos](https://melos.invertase.dev/) once, then run from the repo root:

```sh
dart pub global activate melos

melos run test       # all unit/widget tests (excludes perf + the env-gated dogfood e2e)
melos run analyze    # dart analyze across the workspace
melos run format     # formatting check
melos run            # list every available script
```

## Status

Leonard is a **proof of concept**. The architecture is real and the loop runs end to end,
but APIs will move, coverage is partial, and you should expect rough edges. It is:

- **Flutter only** — not React Native, not native iOS/Android, not the web DOM.
- **Debug/profile mode only** — release builds don't expose the VM-service extensions it needs.
- **Not a codegen or test-authoring tool** — it acts on a _running_ app; it never writes app code.
- **Not a training pipeline** — it collects trajectories; what you do with them is downstream.

Where it's headed: [`docs/leonard_prd_v0.5.md`](docs/leonard_prd_v0.5.md).

## Documentation

- [How Leonard works](docs/how-leonard-works.md) — an illustrated tour of the loop and the extension contract.
- [Extension authoring guide](docs/extension_authoring_guide.md) — write an extension for your stack.
- [PRD v0.5](docs/leonard_prd_v0.5.md) — the full design rationale.
- [Architecture decision records](docs/adrs) — the decisions and why.

## License

[MIT](LICENSE) © 2026 Nico Spencer
