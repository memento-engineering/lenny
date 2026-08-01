/// The pump-able root of the Leonard DevTools extension.
///
/// `LeonardDevToolsExtension` (in `lib/main.dart`) cannot be reached from
/// a VM `flutter test`: `DevToolsExtension` transitively imports
/// `dart:js_interop` / `package:web`, which do not compile for the
/// `flutter_tester` target, and `lib/main.dart` itself imports
/// `dart:html`. This root therefore carries the ordering-sensitive
/// wiring — the [Builder] that defers every `serviceManager` /
/// `dtdManager` read below the DevTools wrapper — with both the wrapper
/// and the globals injected, so `test/extension_root_test.dart` can pump
/// the real ordering logic against Fakes.
library;

import 'package:flutter/material.dart';

import 'leonard_shell.dart';
import 'diagnostics/diagnostics_snapshot.dart';
import 'manifest_probe.dart' show ManifestProbe;
import 'panels/prompt_panel_config_store.dart' show PromptPanelConfigStore;
import 'panels/prompt_panel_controller.dart' show SessionFactory;
import 'panels/provider_config_store.dart' show ProviderConfigStore;

/// Everything [LeonardExtensionRoot] needs out of the DevTools globals.
///
/// A production implementation reads `serviceManager` / `dtdManager` in
/// its constructor, and those globals throw until `DevToolsExtension`'s
/// `State.initState` has run — so a scope may only ever be constructed
/// BELOW the DevTools wrapper. Enforcing that is [LeonardExtensionRoot]'s
/// whole job.
abstract class LeonardDevToolsScope {
  /// Loads the active extension manifest over the live VM service.
  ManifestProbe get manifestProbe;

  /// Builds the in-panel session over the live VM service.
  SessionFactory get sessionFactory;

  /// Loads the current Genesis diagnostics snapshot.
  DiagnosticsSnapshotLoader get diagnosticsSnapshotLoader;

  /// Fires on (re)connect and on main-isolate change, so the shell
  /// re-probes the extension manifest.
  Listenable get probeRetrigger;

  /// Per-provider config persistence (DTD-backed in production).
  ProviderConfigStore get providerConfigStore;

  /// Prompt-form persistence (DTD + localStorage in production).
  PromptPanelConfigStore get promptConfigStore;
}

/// Builds a [LeonardDevToolsScope]. Called from inside the [Builder]
/// below the DevTools wrapper — never during [LeonardExtensionRoot]'s
/// own build.
typedef LeonardDevToolsScopeFactory = LeonardDevToolsScope Function();

/// Wraps [child] in the widget that installs the DevTools globals.
/// Production passes `(child) => DevToolsExtension(child: child)`; the
/// widget test passes a Fake host with the same `initState` contract.
typedef DevToolsWrapper = Widget Function(Widget child);

/// The extension root: DevTools wrapper → [Builder] → [LeonardShell].
///
/// The [Builder] is load-bearing, not cosmetic. It pushes the
/// [scopeFactory] call into a descendant build that runs only after the
/// wrapper's `State.initState`. Resolving the scope in this widget's own
/// `build` reintroduces the `Bad state: 'serviceManager' has not been
/// initialized yet` crash; `test/extension_root_test.dart` fails if it
/// comes back.
class LeonardExtensionRoot extends StatelessWidget {
  /// Creates the root from a DevTools [wrap]per and a [scopeFactory].
  const LeonardExtensionRoot({
    super.key,
    required this.wrap,
    required this.scopeFactory,
  });

  /// Installs the DevTools globals around the child.
  final DevToolsWrapper wrap;

  /// Resolves the globals — only ever called below [wrap].
  final LeonardDevToolsScopeFactory scopeFactory;

  @override
  Widget build(BuildContext context) => wrap(
    Builder(
      builder: (BuildContext context) {
        final LeonardDevToolsScope scope = scopeFactory();
        return LeonardShell(
          manifestProbe: scope.manifestProbe,
          sessionFactory: scope.sessionFactory,
          diagnosticsSnapshotLoader: scope.diagnosticsSnapshotLoader,
          store: scope.providerConfigStore,
          promptConfigStore: scope.promptConfigStore,
          probeRetrigger: scope.probeRetrigger,
        );
      },
    ),
  );
}
