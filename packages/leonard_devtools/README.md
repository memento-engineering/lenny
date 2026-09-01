# leonard_devtools

A plain `leonard_flutter` dependency automatically discovers one Leonard
DevTools extension with Conversation and Diagnostics modes. Diagnostics
requests Genesis diagnostics contract 1
(`ext.leonard.core.get_diagnostics_tree`) only while its panel is open;
no adopter dependency on `leonard_devtools` or `genesis_foundation` is
required. The conversation harness persists trajectories through the
Dart Tooling Daemon (no extra IPC and no `dart:io`).

## Build

The compiled web bundle that DevTools loads is **not committed**. Every
fresh clone (and every rebuild after a change to this package's `lib/`,
`web/`, or `pubspec.yaml`) must run:

```sh
./tool/build_devtools_extension.sh
```

The script runs `dart run devtools_extensions build_and_copy` twice
and populates both `packages/leonard_devtools/extension/devtools/build/`
(used for standalone development) and
`packages/leonard_flutter/extension/devtools/build/` (the host
package whose pubspec dep triggers DevTools auto-discovery in consumer
apps such as `sample_app`).

CI runs the same script before analyze/test, so a PR that breaks the
extension build fails at merge time — there is no committed-bundle
drift to diff against.

## Auto-discovery

The host package `leonard_flutter` ships
`extension/devtools/config.yaml`, so any app whose pubspec transitively
depends on `leonard_flutter` automatically surfaces the **Leonard**
tab in standalone DevTools, the VS Code DevTools view, and the Android Studio
DevTools view. A duplicate `extension/devtools/config.yaml` is kept inside
this package for standalone development against the simulated DevTools
environment.

## Iterating on the panel

Two ways to run the panel while developing it:

### Standalone web (fast iteration)

The `devtools_extensions` simulated environment hosts the extension UI for standalone development.
"Simulated" describes the DevTools host, not its
connections: it accepts real Dart VM Service and DTD connections from an app
launched with `--print-dtd`. Connect interactively with the URI controls, or
supply the percent-encoded `uri` and `dtdUri` query parameters; the extension
manager connects to both real services on load. The standalone panel still has
hot reload and source-level breakpoints with no bundle rebuild
(`tool/build_devtools_extension.sh`) in the loop.

- VS Code: launch the **`leonard_devtools (standalone web)`** config
  (group `4_devtools` in `.vscode/launch.json`).
- CLI equivalent: `flutter run -d chrome --dart-define=use_simulated_environment=true`
  from `packages/leonard_devtools/`.

To make the standalone panel itself observable through Leonard, use the
development-only entrypoint. It installs `LeonardBinding` before mounting the
same `LeonardDevToolsExtension` shell as `lib/main.dart`. Run it only through
`flutter run`, which keeps the DDC debugger attached:

```sh
flutter run -t dev/selfdrive_main.dart -d chrome --dart-define=use_simulated_environment=true
```

The entrypoint lives outside `lib/`; the shipped release extension continues to
build `lib/main.dart` and does not include `leonard_flutter`.

For the fully wired self-drive setup, run this from the repository root:

```sh
./tool/run_panel_selfdrive.sh [sample-app-device-id]
```

The device id defaults to `macos`. The harness launches `sample_app`, serves
`dev/selfdrive_main.dart` with `-d web-server` on fixed port `9101`, opens Chrome
with both real connection URIs percent-encoded into `uri` and `dtdUri`, and
writes the panel's own DWDS VM-service URI to stdout for the outer Leonard
process. It remains attached until the panel exits or you interrupt it.

### In-DevTools (real handshake)

Use to verify the real binding handshake, real `/v1/models` calls, and
real `session.run` end-to-end. This runs the compiled bundle inside a
real DevTools instance attached to `sample_app`.

- VS Code: launch the **`Dogfood: sample_app + leonard_cli`** compound
  (it runs the `Build DevTools Extension` preLaunchTask first). This starts
  the target app and CLI; **open DevTools separately** — click the DevTools
  URL printed in the Run console (or run `dart devtools --vm-service-uri=<uri>`)
  and open the **Leonard** tab.

### Attaching a debugger

- **Dart side:** launch the `leonard_devtools (standalone web)` config
  and set breakpoints in `packages/leonard_devtools/lib/**` — Dart-Code
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
dart pub get -C packages/leonard_devtools
flutter test packages/leonard_devtools
dart analyze packages/leonard_devtools
./tool/check_no_dart_io.sh
```
