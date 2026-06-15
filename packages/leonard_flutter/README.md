# leonard_flutter

Host `WidgetsBinding` for Leonard.

## Usage

```dart
void main() => LeonardBinding.run(MyApp());

class MyApp implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) {
    // Construct Router, ProviderContainer, Dio, etc. *here* — by the
    // time this callback runs, LeonardBinding has already claimed
    // the WidgetsBinding slot, so any WidgetsFlutterBinding.ensureInitialized()
    // call inside (e.g. from go_router 14.x) is an idempotent no-op.
    return LeonardAppConfig(
      plugins: <LeonardExtension>[/* extensions */],
      app: const MaterialApp(home: SizedBox.shrink()),
    );
  }
}
```

`LeonardBinding.run(app)` claims the `WidgetsBinding` slot first, then
hands an `LeonardAppContext` to `app.build(ctx)` and calls `runApp`
inside the binding's stability zone. Outside debug/profile (`kReleaseMode`),
no binding is installed and no extensions are registered, but `app.build` and
`runApp` still run.

The lower-level `LeonardBinding.ensureInitialized(plugins: [...])`
remains for tests, headless agents, and advanced cases that need to own
the install ordering themselves. It throws `StateError` if a foreign
`WidgetsBinding` (e.g. `IntegrationTestWidgetsFlutterBinding`) is already
installed.

## VM service extension namespace

`leonard_flutter` reserves `ext.exploration.*` for all
host- and extension-owned VM service extensions. Format:

    ext.exploration.<namespace>.<suffix>

- `<namespace>` is `core` for host-owned extensions, or an extension's
  `namespace` (matching `^[a-z][a-z0-9_]*$`).
- `<suffix>` is the extension's local name.

The host registers `ext.exploration.core.handshake` from
`LeonardBinding.ensureInitialized(...)`. The harness uses it to
confirm the binding is live and read protocol/version metadata.
Extensions register through `ExtensionContext`, which auto-prefixes.

## DevTools panel

This package ships `extension/devtools/config.yaml` so any app that
transitively depends on `leonard_flutter` automatically surfaces
the **Leonard** tab in DevTools. The compiled web bundle lives at
`extension/devtools/build/` and is **not committed** — rebuild it from
the repo root with:

```sh
./tool/build_devtools_extension.sh
```

See `packages/leonard_devtools/README.md` for the full build
workflow.
