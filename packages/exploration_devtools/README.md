# exploration_devtools

DevTools extension for the Flutter Exploration Agent. Surfaces three tabs
(Prompt, Thinking, Timeline) inside the connected app's DevTools instance and
runs the harness in-panel so trajectories persist via the Dart Tooling Daemon
filesystem APIs (no extra IPC, no `dart:io`). See PRD §22.

## Build

The compiled web bundle that DevTools loads is **not committed**. Every
fresh clone (and every rebuild after a change to this package's `lib/`,
`web/`, or `pubspec.yaml`) must run:

```sh
./tool/build_devtools_extension.sh
```

The script runs `dart run devtools_extensions build_and_copy` twice
and populates both `packages/exploration_devtools/extension/devtools/build/`
(used for standalone development) and
`packages/exploration_flutter/extension/devtools/build/` (the host
package whose pubspec dep triggers DevTools auto-discovery in consumer
apps such as `sample_app`).

CI runs the same script before analyze/test, so a PR that breaks the
extension build fails at merge time — there is no committed-bundle
drift to diff against.

## Auto-discovery

The host package `exploration_flutter` ships
`extension/devtools/config.yaml`, so any app whose pubspec transitively
depends on `exploration_flutter` automatically surfaces the **Exploration**
tab in standalone DevTools, the VS Code DevTools view, and the Android Studio
DevTools view. A duplicate `extension/devtools/config.yaml` is kept inside
this package for standalone development against the simulated DevTools
environment.

## Iterating on the panel

Two ways to run the panel while developing it:

### Standalone web (fast iteration)

Use for widget work, layout, and form behavior — anything that does not
depend on real DTD or real VM-service traffic. The
`devtools_extensions` simulated environment supplies a fake DTD and a
fake VM service, so `lib/main.dart` runs as a plain `flutter run -d
chrome` web app: hot reload on save and source-level breakpoints both
work, with **no** bundle rebuild (`tool/build_devtools_extension.sh`)
in the loop.

- VS Code: launch the **`exploration_devtools (standalone web)`** config
  (group `4_devtools` in `.vscode/launch.json`).
- CLI equivalent: `flutter run -d chrome --dart-define=use_simulated_environment=true`
  from `packages/exploration_devtools/`.

### In-DevTools (real handshake)

Use to verify the real binding handshake, real `/v1/models` calls, and
real `session.run` end-to-end. This runs the compiled bundle inside a
real DevTools instance attached to `sample_app`.

- VS Code: launch the **`Dogfood: sample_app + exploration_cli`** compound
  (it runs the `Build DevTools Extension` preLaunchTask first), then open
  DevTools -> **Exploration** tab.

### Attaching a debugger

- **Dart side:** launch the `exploration_devtools (standalone web)` config
  and set breakpoints in `packages/exploration_devtools/lib/**` — Dart-Code
  owns the VM service for this target, so they bind immediately.
- **Browser side:** open Chrome DevTools on the served tab (the one
  `flutter run -d chrome` opened) — debug web builds ship source maps, so
  you can set breakpoints in the `.dart` sources from the Sources panel.

## Minimum versions

- `devtools_extensions: ^0.4.0` — pinned in `pubspec.yaml`.
- Flutter `>= 3.41.0` — required by `package:devtools_extensions` and
  enforced via this package's `environment` constraint.
- DevTools shipped with the above Flutter releases (the IDE plugins follow
  the same channel).

PRD §22 captures the rationale for the in-panel architecture.

## CORS for local MLX inference

The DevTools panel is served from DevTools' own web origin, so any
browser-originated HTTP request to a local inference server (`mlx-vlm`,
SGLang, vLLM) crosses an origin boundary and requires permissive CORS
headers on the server side:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST,OPTIONS
Access-Control-Allow-Headers: Content-Type,Authorization
```

Add these to the inference server's configuration (or the reverse proxy in
front of it). Without them the panel's HTTP requests will fail with an
opaque CORS error in the browser console even though the server is
reachable.

## Development

```sh
dart pub get -C packages/exploration_devtools
flutter test packages/exploration_devtools
dart analyze packages/exploration_devtools
./tool/check_no_dart_io.sh
```
