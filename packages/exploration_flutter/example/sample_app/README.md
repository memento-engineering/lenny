# sample_app

Moderate-complexity macOS Flutter app used as the dogfood + PRD §23
success-criteria fixture for the Flutter Exploration Agent. Exercises
all three reference plugins end-to-end:

| Plugin                       | Surface in this app                                     |
| ---------------------------- | ------------------------------------------------------- |
| `RouterPlugin` (go_router)   | 5 routes, auth-guard redirect, shared `navigatorKey`     |
| `RiverpodExplorationPlugin`  | shared `ProviderContainer` + observer; auth + settings   |
| `ExplorationDioPlugin`       | one `Dio` instance; every endpoint logged via interceptor |

PRD §23 headline goal: **log in via Navigator-managed routes →
settings → change Riverpod-managed setting → log out**. This app is
the canonical fixture that goal is verified against.

## Prerequisites

- Flutter ≥ 3.41.0 (matches workspace constraint)
- macOS (Apple Silicon or Intel) — only platform scaffolded for v1
- Xcode CLT installed (`xcode-select --install`)

## Install

From the **workspace root** (`/Users/.../lenny`):

```bash
flutter pub get
```

The workspace pubspec resolves all packages in one shot. No need to
run `pub get` inside `sample_app/`.

If you ever need to regenerate the macOS scaffolding (e.g., new
Flutter version, missing `Runner.xcodeproj`):

```bash
cd packages/exploration_flutter/example/sample_app
flutter create . --platforms=macos --project-name=sample_app --org=com.lenny --empty
# then re-apply this repo's pubspec.yaml + analysis_options.yaml on top.
```

## Run

```bash
cd packages/exploration_flutter/example/sample_app
flutter run -d macos
```

`main.dart` uses `ExplorationBinding.run(SampleApp())` so binding
installation precedes router/container construction.

A macOS window opens showing the Login screen. Hardcoded demo
credentials:

- email: `demo@example.com`
- password: `password`

Anything else returns HTTP 401 with an inline `Invalid credentials`
error rendered under the Sign In button (`ValueKey('login_error')`).
Determinism guarantee: there is no real network — every HTTP call is
intercepted by an in-process `FakeApiAdapter`, and Riverpod state is
in-memory only (no `SharedPreferences`).

## Dogfood with `exploration_cli`

When `flutter run -d macos` boots, it prints a line like:

```
The Dart VM service is listening on ws://127.0.0.1:54321/abc=/ws
```

Grep that out of the run output:

```bash
flutter run -d macos 2>&1 | grep -m1 'Dart VM service is listening'
```

Then point `exploration_cli` at the URI:

```bash
exploration_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal 'Log in with demo@example.com/password, change the theme to dark, then log out.' \
  --plugins router,riverpod,dio
```

The agent should produce a JSONL trajectory whose actions cover login
form fill → submit → navigate to settings → flip theme → log out, with:

- a router observation transitioning `login → home → settings`,
- a riverpod `recent_state_changes` entry naming `settings`,
- a dio `recent_completed` entry for `POST /auth/login`.

## Test

```bash
cd packages/exploration_flutter/example/sample_app
flutter test
```

Two suites run:

1. `test/fake_api_adapter_test.dart` — covers good login (200+token),
   bad login (401), `/profile`, `/items`, unknown path (404),
   simulated latency.
2. `test/login_widget_test.dart` — pumps the app, exercises Sign In
   with demo creds (lands on Home), then with bad creds (renders the
   `login_error` text).

## Architecture cheat sheet

`lib/main.dart` constructs **one** `ProviderContainer` (with
`ExplorationProviderObserver` installed) and **one** `Dio`, then
hands the same instances to:

- `UncontrolledProviderScope(container: ...)` for the widget tree
- `RiverpodExplorationPlugin(container: ..., observer: ...)`
- `ExplorationDioPlugin(dio)`
- `RouterPlugin(navigatorKey: ..., routerDelegate: router.routerDelegate)`

…before calling `ExplorationBinding.ensureInitialized(plugins: ...)`.
That single shared-instance principle is what lets the agent see the
real app, not an instrumented copy.

## Out of scope

- iOS / Android / Web (macOS only for v1).
- Real backend or real auth.
- Disk persistence (no SharedPreferences).
- Production-quality UI polish.
