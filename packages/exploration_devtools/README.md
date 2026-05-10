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
