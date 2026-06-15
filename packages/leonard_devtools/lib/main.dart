import 'dart:convert' show utf8;

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:leonard_agent/leonard_agent.dart'
    show BindingNotInitializedError, LeonardSession, ExtensionManifestEntry;
import 'package:flutter/material.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;

// ignore: deprecated_member_use
import 'dart:html' show window;

import 'src/leonard_shell.dart';
import 'src/manifest_probe.dart' show probeManifest;
import 'src/panels/prompt_panel_config_store.dart' show DtdPromptPanelConfigStore;
import 'src/panels/provider_config_store.dart' show DtdProviderConfigStore;

void main() => runApp(const LeonardDevToolsExtension());

/// Top-level extension widget. Wraps [LeonardShell] in [DevToolsExtension]
/// so DevTools provides Material theming, the VM service, and DTD.
///
/// `serviceManager` is a top-level getter that throws until
/// `DevToolsExtension`'s State.initState has run. Any read at or above
/// `DevToolsExtension` in the widget tree fails on the first frame with
/// `Bad state: 'serviceManager' has not been initialized yet`. The
/// [Builder] below pushes the reads into a descendant build call that
/// runs only after `DevToolsExtension` has initialized — see
/// devtools_extensions's own README ("serviceManager getters … below
/// the DevToolsExtension widget in the widget tree").
///
/// The DevTools extension is a Flutter **web** build, so it must never
/// open its own VM-service websocket (`package:vm_service/vm_service_io.dart`
/// pulls in `dart:io`, which throws `Unsupported operation: Platform._version`
/// on web — see lenny-dzh). Instead the manifest probe and the
/// Start-button session both reuse the live, web-safe connection DevTools
/// already holds: `serviceManager.service` (a `package:web` JS websocket)
/// pinned to `serviceManager.isolateManager.mainIsolate`.
class LeonardDevToolsExtension extends StatelessWidget {
  const LeonardDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) => DevToolsExtension(
        child: Builder(
          builder: (BuildContext context) {
            // Loads the plugin manifest over the live serviceManager VM
            // service. When the service / main isolate aren't ready yet,
            // throw BindingNotInitializedError → the host shows
            // "Binding not detected" rather than an uncaught dart:io
            // crash; the probeRetrigger below re-runs it once they are.
            Future<List<ExtensionManifestEntry>> probe() async {
              final vm = serviceManager.service;
              final id = serviceManager.isolateManager.mainIsolate.value?.id;
              if (vm == null || id == null) {
                throw BindingNotInitializedError();
              }
              return probeManifest(vm, id);
            }

            // Builds the in-panel session over the same connection. A
            // null service / isolate here is a clear StateError, not an
            // "Unsupported operation" crash.
            Future<LeonardSession> session() async {
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

            // Config files land at <workspaceRoot>/.dart_tool/<key>.json.
            // When DTD is not connected (standalone web / simulated env)
            // reads return null and writes are no-ops, leaving the panel
            // functional on the in-memory default.
            final store = DtdProviderConfigStore(
              read: (key) async {
                final dtd = dtdManager.connection.value;
                if (dtd == null) return null;
                final roots = await dtdManager.workspaceRoots();
                if (roots == null || roots.ideWorkspaceRoots.isEmpty) {
                  return null;
                }
                final uri = Uri.file(
                  '${roots.ideWorkspaceRoots.first.toFilePath()}'
                  '/.dart_tool/$key.json',
                );
                try {
                  final file =
                      await dtd.readFileAsString(uri, encoding: utf8);
                  return file.content;
                } on RpcException catch (e) {
                  if (e.code == RpcErrorCodes.kFileDoesNotExist) return null;
                  rethrow;
                }
              },
              write: (key, value) async {
                final dtd = dtdManager.connection.value;
                if (dtd == null) return;
                final roots = await dtdManager.workspaceRoots();
                if (roots == null || roots.ideWorkspaceRoots.isEmpty) return;
                final uri = Uri.file(
                  '${roots.ideWorkspaceRoots.first.toFilePath()}'
                  '/.dart_tool/$key.json',
                );
                await dtd.writeFileAsString(uri, value, encoding: utf8);
              },
            );

            // Prompt config: DTD primary (per-workspace file), localStorage
            // fallback (per-origin). PromptPanelConfig carries no secrets,
            // so plain JSON is safe.
            final promptConfigStore = DtdPromptPanelConfigStore(
              read: (key) async {
                final dtd = dtdManager.connection.value;
                if (dtd == null) return null;
                final roots = await dtdManager.workspaceRoots();
                if (roots == null || roots.ideWorkspaceRoots.isEmpty) {
                  return null;
                }
                final uri = Uri.file(
                  '${roots.ideWorkspaceRoots.first.toFilePath()}'
                  '/.dart_tool/$key.json',
                );
                try {
                  final file =
                      await dtd.readFileAsString(uri, encoding: utf8);
                  return file.content;
                } on RpcException catch (e) {
                  if (e.code == RpcErrorCodes.kFileDoesNotExist) return null;
                  rethrow;
                }
              },
              write: (key, value) async {
                final dtd = dtdManager.connection.value;
                if (dtd == null) return;
                final roots = await dtdManager.workspaceRoots();
                if (roots == null || roots.ideWorkspaceRoots.isEmpty) return;
                final uri = Uri.file(
                  '${roots.ideWorkspaceRoots.first.toFilePath()}'
                  '/.dart_tool/$key.json',
                );
                await dtd.writeFileAsString(uri, value, encoding: utf8);
              },
              // ignore: deprecated_member_use
              localRead: (key) => window.localStorage[key],
              // ignore: deprecated_member_use
              localWrite: (key, value) {
                // ignore: deprecated_member_use
                window.localStorage[key] = value;
              },
            );

            return LeonardShell(
              manifestProbe: probe,
              sessionFactory: session,
              store: store,
              promptConfigStore: promptConfigStore,
              // Reconnects (hot-restart of the target app) flip
              // connectedState; the main isolate may appear slightly
              // after. The shell listens to either and re-probes the
              // manifest. Read inside the Builder so the accesses happen
              // after DevToolsExtension.initState — not in the parent's
              // build, where serviceManager throws.
              probeRetrigger: Listenable.merge(<Listenable?>[
                serviceManager.connectedState,
                serviceManager.isolateManager.mainIsolate,
              ]),
            );
          },
        ),
      );
}
