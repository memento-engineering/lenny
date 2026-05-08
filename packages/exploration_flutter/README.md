# exploration_flutter

Host `WidgetsBinding` for the Flutter Exploration Agent.

## Usage

```dart
void main() {
  ExplorationBinding.ensureInitialized(plugins: const [/* plugins */]);
  runApp(const MyApp());
}
```

`ExplorationBinding.ensureInitialized` is a no-op outside debug and profile
mode. It throws `StateError` if a foreign `WidgetsBinding`
(e.g. `IntegrationTestWidgetsFlutterBinding`) is already installed.

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
