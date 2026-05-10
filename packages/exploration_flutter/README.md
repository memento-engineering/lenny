# exploration_flutter

Host `WidgetsBinding` for the Flutter Exploration Agent.

## Usage

```dart
void main() => ExplorationBinding.run(MyApp());

class MyApp implements ExplorationApp {
  @override
  ExplorationAppConfig build(ExplorationAppContext ctx) {
    // Construct Router, ProviderContainer, Dio, etc. *here* — by the
    // time this callback runs, ExplorationBinding has already claimed
    // the WidgetsBinding slot, so any WidgetsFlutterBinding.ensureInitialized()
    // call inside (e.g. from go_router 14.x) is an idempotent no-op.
    return ExplorationAppConfig(
      plugins: <ExplorationPlugin>[/* plugins */],
      app: const MaterialApp(home: SizedBox.shrink()),
    );
  }
}
```

`ExplorationBinding.run(app)` claims the `WidgetsBinding` slot first, then
hands an `ExplorationAppContext` to `app.build(ctx)` and calls `runApp`
inside the binding's stability zone. Outside debug/profile (`kReleaseMode`),
no binding is installed and no plugins are registered, but `app.build` and
`runApp` still run.

The lower-level `ExplorationBinding.ensureInitialized(plugins: [...])`
remains for tests, headless agents, and advanced cases that need to own
the install ordering themselves. It throws `StateError` if a foreign
`WidgetsBinding` (e.g. `IntegrationTestWidgetsFlutterBinding`) is already
installed.

## VM service extension namespace

`exploration_flutter` reserves `ext.flutter.exploration.*` for all
host- and plugin-owned VM service extensions. Format:

    ext.flutter.exploration.<namespace>.<suffix>

- `<namespace>` is `core` for host-owned extensions, or a plugin's
  `namespace` (matching `^[a-z][a-z0-9_]*$`).
- `<suffix>` is the extension's local name.

The host registers `ext.flutter.exploration.core.handshake` from
`ExplorationBinding.ensureInitialized(...)`. The harness uses it to
confirm the binding is live and read protocol/version metadata.
Plugins register through `PluginContext` (cx6.3), which auto-prefixes.
