/// Regression coverage for the DevTools-globals ordering bug class AT
/// THE ROOT BOUNDARY: the globals must be resolved BELOW the wrapper
/// that installs them, never during the root's own build.
///
/// `lib/main.dart`'s `LeonardDevToolsExtension` cannot be pumped here —
/// `DevToolsExtension` transitively imports `dart:js_interop` /
/// `package:web`, which do not compile for `flutter_tester`, and
/// `lib/main.dart` imports `dart:html`. The ordering logic therefore
/// lives in `LeonardExtensionRoot`, and this file pumps THAT — the real
/// root, the real Builder, the real LeonardShell construction — against
/// a Fake wrapper with devtools_extensions' `initState` contract.
/// `test/main_wiring_guard_test.dart` gates the other half (that
/// `lib/main.dart` actually routes through this root).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:leonard_agent/leonard_agent.dart'
    show ExtensionManifestEntry, LeonardSession;
import 'package:leonard_devtools/src/extension_root.dart';
import 'package:leonard_devtools/src/diagnostics/diagnostics_snapshot.dart';
import 'package:leonard_devtools/src/leonard_shell.dart';
import 'package:leonard_devtools/src/manifest_probe.dart' show ManifestProbe;
import 'package:leonard_devtools/src/panels/prompt_panel_config_store.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_controller.dart'
    show SessionFactory;
import 'package:leonard_devtools/src/panels/provider_config_store.dart';

/// Verbatim shape of the message devtools_extensions throws from
/// `_accessGlobalOrThrow` (devtools_extensions-0.4.0
/// `src/template/devtools_extension.dart`).
const String _kNotInitialized =
    "'serviceManager' has not been initialized yet. You can only access "
    "'serviceManager' below the 'DevToolsExtension' widget in the widget "
    'tree.';

/// Fake stand-in for the devtools_extensions globals. [ready] flips true
/// in [_FakeDevToolsHost]'s `initState` — exactly where the real
/// `DevToolsExtension` calls `setGlobal(ServiceManager, ServiceManager())`.
class _FakeGlobals {
  bool ready = false;
  final List<String> events = <String>[];
  final ValueNotifier<int> retrigger = ValueNotifier<int>(0);
  int probeCalls = 0;

  void requireReady() {
    if (!ready) throw StateError(_kNotInitialized);
  }
}

/// Fake `DevToolsExtension`: installs the globals in `initState` and
/// supplies the `MaterialApp` the real wrapper supplies.
class _FakeDevToolsHost extends StatefulWidget {
  const _FakeDevToolsHost({required this.globals, required this.child});

  final _FakeGlobals globals;
  final Widget child;

  @override
  State<_FakeDevToolsHost> createState() => _FakeDevToolsHostState();
}

class _FakeDevToolsHostState extends State<_FakeDevToolsHost> {
  @override
  void initState() {
    super.initState();
    widget.globals.ready = true;
    widget.globals.events.add('host.initState');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(home: widget.child);
}

Future<List<ExtensionManifestEntry>> _noManifest() async =>
    const <ExtensionManifestEntry>[];

Future<LeonardSession> _noSession() async =>
    throw StateError('no session in this test');

Future<TreeSnapshot> _noDiagnostics() async =>
    throw StateError('no diagnostics in this test');

/// Fake [LeonardDevToolsScope]. Its constructor touches the globals in
/// the same position `_LiveDevToolsScope`'s initializer list does.
class _FakeScope implements LeonardDevToolsScope {
  _FakeScope(this._globals, {bool checkOrdering = true}) {
    if (checkOrdering) {
      _globals.requireReady();
      _globals.events.add('scope.resolve');
    }
  }

  final _FakeGlobals _globals;

  @override
  final ProviderConfigStore providerConfigStore = InMemoryProviderConfigStore();

  @override
  final PromptPanelConfigStore promptConfigStore =
      InMemoryPromptPanelConfigStore();

  @override
  Listenable get probeRetrigger => _globals.retrigger;

  @override
  ManifestProbe get manifestProbe => () async {
    _globals.probeCalls += 1;
    return _noManifest();
  };

  @override
  SessionFactory get sessionFactory => _noSession;

  @override
  DiagnosticsSnapshotLoader get diagnosticsSnapshotLoader => _noDiagnostics;
}

/// The pre-fix shape: the scope is resolved in the root's OWN build,
/// above the host that installs the globals. Kept in the test as the
/// falsifier — it proves the Fake reproduces the real hazard, so the
/// green tests above are not vacuous.
class _PreFixRoot extends StatelessWidget {
  const _PreFixRoot({required this.globals});

  final _FakeGlobals globals;

  @override
  Widget build(BuildContext context) {
    final LeonardDevToolsScope scope = _FakeScope(globals);
    return _FakeDevToolsHost(
      globals: globals,
      child: LeonardShell(
        manifestProbe: scope.manifestProbe,
        sessionFactory: scope.sessionFactory,
        diagnosticsSnapshotLoader: scope.diagnosticsSnapshotLoader,
        store: scope.providerConfigStore,
        promptConfigStore: scope.promptConfigStore,
        probeRetrigger: scope.probeRetrigger,
      ),
    );
  }
}

Widget _root(_FakeGlobals globals, {LeonardDevToolsScope? scope}) =>
    LeonardExtensionRoot(
      wrap: (Widget child) => _FakeDevToolsHost(globals: globals, child: child),
      scopeFactory: () => scope ?? _FakeScope(globals),
    );

void main() {
  testWidgets('the real root pumps with no serviceManager StateError', (
    tester,
  ) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_root(globals));
    expect(tester.takeException(), isNull);
    expect(find.byType(LeonardShell), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the scope resolves only after the wrapper initState', (
    tester,
  ) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_root(globals));
    await tester.pumpAndSettle();
    expect(globals.events, <String>['host.initState', 'scope.resolve']);
  });

  testWidgets('the pre-fix shape throws the not-initialized StateError', (
    tester,
  ) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_PreFixRoot(globals: globals));
    final Object? error = tester.takeException();
    expect(error, isA<StateError>());
    expect(error.toString(), contains('has not been initialized yet'));
    expect(globals.events, isEmpty);
  });

  testWidgets('the shell renders below the root', (tester) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_root(globals));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt.goal')), findsOneWidget);
    expect(find.byKey(const Key('runStatus.idle')), findsOneWidget);
    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsNothing);
  });

  testWidgets("the scope's manifestProbe reaches the shell", (tester) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_root(globals));
    await tester.pumpAndSettle();
    expect(globals.probeCalls, 1);
  });

  testWidgets("the scope's probeRetrigger reaches the shell", (tester) async {
    final globals = _FakeGlobals();
    await tester.pumpWidget(_root(globals));
    await tester.pumpAndSettle();
    expect(globals.probeCalls, 1);
    globals.retrigger.value += 1;
    await tester.pumpAndSettle();
    expect(globals.probeCalls, 2);
  });

  testWidgets("the scope's stores are handed to the shell by identity", (
    tester,
  ) async {
    final globals = _FakeGlobals();
    final scope = _FakeScope(globals, checkOrdering: false);
    await tester.pumpWidget(_root(globals, scope: scope));
    await tester.pumpAndSettle();
    final LeonardShell shell = tester.widget<LeonardShell>(
      find.byType(LeonardShell),
    );
    expect(shell.store, same(scope.providerConfigStore));
    expect(shell.promptConfigStore, same(scope.promptConfigStore));
    expect(shell.probeRetrigger, same(scope.probeRetrigger));
  });
}
