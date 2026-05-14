/// Typed wrapper around `package:vm_service` for the harness's binding
/// service-extension calls.
///
/// This is the only place inside `package:exploration_agent` that depends
/// on `package:vm_service`. Everything else routes through this seam so
/// later stories (.12 observation, .14 model provider, .17 validator,
/// .19 writer, .21 DevTools transport) share one abstraction.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'errors.dart';
import 'types.dart';

/// JSON-RPC standard "method not found" code — what the VM service
/// returns when a service extension is not registered (i.e. the
/// target app's `ExplorationBinding` is absent).
const int _kMethodNotFoundRpc = -32601;

/// Service-extension method names exchanged with `ExplorationBinding`.
const String _extHandshake = 'ext.flutter.exploration.core.handshake';

/// Typed VM-service client used by [ExplorationSession].
///
/// Two construction modes:
///   - [connect] (async) — opens its own websocket via
///     `package:vm_service/vm_service_io.dart`. CLI-only: that import
///     transitively pulls in `dart:io`, which throws on web.
///   - [fromVmService] (sync) — wraps an already-connected [VmService]
///     supplied by the caller (e.g. the DevTools extension's
///     `serviceManager.service`). Web-safe: only the core
///     `package:vm_service/vm_service.dart` is touched.
///
/// Tests inject a fake via [VmServiceClient.forTest].
class VmServiceClient {
  VmServiceClient._(this._vm, this._isolateId);

  /// Wrap an already-connected [VmService] and pin [isolateId] as the
  /// binding's home isolate.
  ///
  /// Web-safe: pulls in only `package:vm_service/vm_service.dart` — no
  /// `dart:io`. The DevTools extension uses this to reuse the live
  /// `serviceManager.service` connection rather than opening its own.
  /// The caller owns the connection's lifetime; [dispose] still
  /// forwards to [VmService.dispose], so callers that did not create
  /// the connection should not call [dispose].
  factory VmServiceClient.fromVmService(VmService vm, String isolateId) {
    return VmServiceClient._(vm, isolateId);
  }

  /// Test-only alias for [fromVmService]. Retained so existing tests
  /// compile unchanged; new code should use [fromVmService].
  @visibleForTesting
  factory VmServiceClient.forTest(VmService vm, String isolateId) {
    return VmServiceClient.fromVmService(vm, isolateId);
  }

  final VmService _vm;
  final String _isolateId;

  /// Connect to a running app's VM service `wsUri` and pin the first
  /// isolate as the binding's home.
  ///
  /// Importing `package:vm_service/vm_service_io.dart` transitively pulls
  /// in `dart:io`. The library-level CI guard
  /// (`tool/check_no_dart_io.dart`) checks for *direct* `dart:io` imports
  /// in `lib/`; story .21 will swap this entrypoint for a conditional
  /// import / DevTools-supplied `VmService`.
  static Future<VmServiceClient> connect(Uri wsUri) async {
    final VmService vm = await vmServiceConnectUri(wsUri.toString());
    final VM state = await vm.getVM();
    final List<IsolateRef> isolates = state.isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      throw StateError(
        'VM service connection has no isolates; cannot bind '
        'ExplorationBinding to a target isolate.',
      );
    }
    final String? id = isolates.first.id;
    if (id == null) {
      throw StateError('First isolate has no id.');
    }
    return VmServiceClient._(vm, id);
  }

  /// Exchange the `ext.flutter.exploration.core.handshake` contract
  /// version and active plugin manifest.
  ///
  /// Throws [BindingNotInitializedError] when the extension is absent
  /// (RPC error code `-32601`, "method not found").
  Future<HandshakeResult> handshake() async {
    final Map<String, dynamic> json =
        await _safeCall(_extHandshake, const <String, dynamic>{});
    final Object? rawVersion = json['protocolVersion'] ?? json['contractVersion'];
    final Object? rawPlugins = json['plugins'];
    if (rawVersion is! String) {
      throw StateError(
        'Handshake response missing or malformed protocolVersion: $rawVersion',
      );
    }
    final List<PluginManifestEntry> plugins = <PluginManifestEntry>[];
    if (rawPlugins is List) {
      for (final Object? entry in rawPlugins) {
        if (entry is! Map) continue;
        final Object? namespace = entry['namespace'];
        final Object? tools = entry['tools'];
        if (namespace is! String) continue;
        final List<String> toolList = <String>[];
        if (tools is List) {
          for (final Object? tool in tools) {
            if (tool is String) toolList.add(tool);
          }
        }
        plugins.add(
          PluginManifestEntry(namespace: namespace, tools: toolList),
        );
      }
    }
    return HandshakeResult(contractVersion: rawVersion, plugins: plugins);
  }

  /// Invoke the per-tool VM service extension that the binding registers
  /// via `PluginContext.registerExtension`:
  /// `ext.flutter.exploration.<namespace>.<tool>`.
  ///
  /// [name] must be the fully-qualified `<namespace>.<tool>` token that
  /// `buildPluginTools` emits and `LoopHost.executeAction` documents
  /// (e.g. `'core.tap'`, `'router.go'`). Throws [ArgumentError] when
  /// [name] is unqualified or has a leading/trailing dot.
  ///
  /// Each value in [args] is JSON-encoded on the wire so the binding's
  /// `_decodeParams`/`_tryDecode` (`core_plugin.dart:156-172`) round-trips
  /// nested maps and lists. Scalars survive either form; encoding
  /// uniformly avoids special-casing.
  Future<Map<String, dynamic>> executeAction(
    String name,
    Map<String, dynamic> args,
  ) {
    final int dot = name.indexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      throw ArgumentError.value(
        name,
        'name',
        'action name must be qualified as <namespace>.<tool>',
      );
    }
    final String namespace = name.substring(0, dot);
    final String tool = name.substring(dot + 1);
    final String ext = 'ext.flutter.exploration.$namespace.$tool';
    final Map<String, dynamic> encoded = <String, dynamic>{
      for (final MapEntry<String, dynamic> e in args.entries)
        e.key: jsonEncode(e.value),
    };
    return _safeCall(ext, encoded);
  }

  /// Generic escape hatch for plugin-provided extensions (used by .12 to
  /// pull plugin contributions). The [extension] string is passed
  /// through verbatim.
  Future<Map<String, dynamic>> callExtension(
    String extension,
    Map<String, dynamic> args,
  ) =>
      _safeCall(extension, args);

  /// Tear down the underlying VM service connection.
  Future<void> dispose() => _vm.dispose();

  Future<Map<String, dynamic>> _safeCall(
    String ext,
    Map<String, dynamic> args,
  ) async {
    try {
      final Response r = await _vm.callServiceExtension(
        ext,
        isolateId: _isolateId,
        args: args,
      );
      return r.json ?? const <String, dynamic>{};
    } on RPCError catch (e) {
      if (ext == _extHandshake && e.code == _kMethodNotFoundRpc) {
        throw BindingNotInitializedError();
      }
      rethrow;
    }
  }
}
