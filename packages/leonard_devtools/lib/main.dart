import 'dart:convert' show utf8;

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:leonard_agent/leonard_agent.dart'
    show BindingNotInitializedError, LeonardSession, ExtensionManifestEntry;
import 'package:flutter/material.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:vm_service/vm_service.dart' show Response;

// ignore: deprecated_member_use
import 'dart:html' show window;

import 'src/extension_root.dart';
import 'src/diagnostics/diagnostics_snapshot.dart';
import 'src/manifest_probe.dart' show ManifestProbe, probeManifest;
import 'src/panels/prompt_panel_config_store.dart'
    show DtdPromptPanelConfigStore, PromptPanelConfigStore;
import 'src/panels/prompt_panel_controller.dart' show SessionFactory;
import 'src/panels/provider_config_store.dart'
    show DtdProviderConfigStore, ProviderConfigStore;

void main() => runApp(const LeonardDevToolsExtension());

/// Top-level extension widget. Wraps the Leonard shell in
/// [DevToolsExtension] so DevTools provides Material theming, the VM
/// service, and DTD.
///
/// `serviceManager` is a top-level getter that throws until
/// `DevToolsExtension`'s State.initState has run. Any read at or above
/// `DevToolsExtension` in the widget tree fails on the first frame with
/// `Bad state: 'serviceManager' has not been initialized yet`. Every
/// such read therefore lives in [_LiveDevToolsScope], which
/// [LeonardExtensionRoot] constructs from inside a [Builder] that runs
/// only after `DevToolsExtension` has initialized — see
/// devtools_extensions's own README ("serviceManager getters … below
/// the DevToolsExtension widget in the widget tree"). This widget's own
/// build reads no global, which `test/main_wiring_guard_test.dart`
/// enforces at the source level.
///
/// The DevTools extension is a Flutter **web** build, so it must never
/// open its own VM-service websocket (which is unsupported on web). Instead
/// the manifest probe and the Start-button session both
/// reuse the live, web-safe connection DevTools already holds:
/// `serviceManager.service` (a `package:web` JS websocket) pinned to
/// `serviceManager.isolateManager.mainIsolate`.
class LeonardDevToolsExtension extends StatelessWidget {
  const LeonardDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) => LeonardExtensionRoot(
    wrap: (Widget child) => DevToolsExtension(child: child),
    scopeFactory: _LiveDevToolsScope.new,
  );
}

/// The production [LeonardDevToolsScope]. Every member reads the DevTools
/// globals, so it is constructed ONLY from inside
/// [LeonardExtensionRoot]'s [Builder] — below `DevToolsExtension`.
/// Constructing it during a parent build is the crash described above.
class _LiveDevToolsScope implements LeonardDevToolsScope {
  _LiveDevToolsScope()
    : // Reconnects (hot-restart of the target app) flip connectedState;
      // the main isolate may appear slightly after. The shell listens to
      // either and re-probes the manifest.
      probeRetrigger = Listenable.merge(<Listenable?>[
        serviceManager.connectedState,
        serviceManager.isolateManager.mainIsolate,
      ]),
      // Config files land at <workspaceRoot>/.dart_tool/<key>.json.
      // When DTD is not connected (standalone web / simulated env)
      // reads return null and writes are no-ops, leaving the panel
      // functional on the in-memory default.
      providerConfigStore = DtdProviderConfigStore(
        read: _dtdRead,
        write: _dtdWrite,
      ),
      // Prompt config: DTD primary (per-workspace file), localStorage
      // fallback (per-origin). PromptPanelConfig carries no secrets, so
      // plain JSON is safe.
      promptConfigStore = DtdPromptPanelConfigStore(
        read: _dtdRead,
        write: _dtdWrite,
        localRead: _localRead,
        localWrite: _localWrite,
      );

  @override
  final Listenable probeRetrigger;

  @override
  final ProviderConfigStore providerConfigStore;

  @override
  final PromptPanelConfigStore promptConfigStore;

  @override
  ManifestProbe get manifestProbe => _probe;

  @override
  SessionFactory get sessionFactory => _session;

  @override
  DiagnosticsSnapshotLoader get diagnosticsSnapshotLoader =>
      _loadDiagnosticsSnapshot;

  /// Loads one on-demand diagnostics snapshot over the borrowed DevTools
  /// VM connection — the sibling extension, no policy arguments.
  static Future<TreeSnapshot> _loadDiagnosticsSnapshot() async {
    final vm = serviceManager.service;
    final String? isolateId =
        serviceManager.isolateManager.mainIsolate.value?.id;
    if (vm == null || isolateId == null) {
      throw StateError('VM service / main isolate not available');
    }
    final Response response = await vm.callServiceExtension(
      '$kLeonardExtensionPrefix.core.get_diagnostics_tree',
      isolateId: isolateId,
    );
    return decodeDiagnosticsSnapshot(
      Map<String, Object?>.from(
        response.json ?? const <String, Object?>{},
      ),
    );
  }

  /// Loads the extension manifest over the live serviceManager VM
  /// service. When the service / main isolate aren't ready yet, throw
  /// BindingNotInitializedError → the host shows "Binding not detected"
  /// rather than an uncaught platform crash; probeRetrigger re-runs it
  /// once they are.
  static Future<List<ExtensionManifestEntry>> _probe() async {
    final vm = serviceManager.service;
    final id = serviceManager.isolateManager.mainIsolate.value?.id;
    if (vm == null || id == null) {
      throw BindingNotInitializedError();
    }
    return probeManifest(vm, id);
  }

  /// Builds the in-panel session over the same connection. A null
  /// service / isolate here is a clear StateError, not an "Unsupported
  /// operation" crash.
  static Future<LeonardSession> _session() async {
    final vm = serviceManager.service;
    final id = serviceManager.isolateManager.mainIsolate.value?.id;
    if (vm == null || id == null) {
      throw StateError(
        'VM service / main isolate not available — cannot start '
        'a Leonard session yet.',
      );
    }
    return LeonardSession.fromVmService(vm, id);
  }

  static Future<Uri?> _configUri(String key) async {
    final dtd = dtdManager.connection.value;
    if (dtd == null) return null;
    final roots = await dtdManager.workspaceRoots();
    if (roots == null || roots.ideWorkspaceRoots.isEmpty) return null;
    return Uri.file(
      '${roots.ideWorkspaceRoots.first.toFilePath()}/.dart_tool/$key.json',
    );
  }

  static Future<String?> _dtdRead(String key) async {
    final dtd = dtdManager.connection.value;
    final uri = await _configUri(key);
    if (dtd == null || uri == null) return null;
    try {
      final file = await dtd.readFileAsString(uri, encoding: utf8);
      return file.content;
    } on RpcException catch (e) {
      if (e.code == RpcErrorCodes.kFileDoesNotExist) return null;
      rethrow;
    }
  }

  static Future<void> _dtdWrite(String key, String value) async {
    final dtd = dtdManager.connection.value;
    final uri = await _configUri(key);
    if (dtd == null || uri == null) return;
    await dtd.writeFileAsString(uri, value, encoding: utf8);
  }

  // ignore: deprecated_member_use
  static String? _localRead(String key) => window.localStorage[key];

  static void _localWrite(String key, String value) {
    // ignore: deprecated_member_use
    window.localStorage[key] = value;
  }
}
