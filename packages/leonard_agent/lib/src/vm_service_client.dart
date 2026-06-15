/// Typed wrapper around `package:vm_service` for the harness's binding
/// service-extension calls.
///
/// This is the only place inside `package:leonard_agent` that depends
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
/// target app's `LeonardBinding` is absent).
const int _kMethodNotFoundRpc = -32601;

/// Service-extension method names exchanged with `LeonardBinding`.
const String _extHandshake = 'ext.exploration.core.handshake';

/// Typed VM-service client used by [LeonardSession].
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
  VmServiceClient._(this._vm, this._isolateId, {bool ownsConnection = false})
    : _ownsConnection = ownsConnection;

  /// Wrap an already-connected [VmService] and pin [isolateId] as the
  /// binding's home isolate.
  ///
  /// Web-safe: pulls in only `package:vm_service/vm_service.dart` — no
  /// `dart:io`. The DevTools extension uses this to reuse the live
  /// `serviceManager.service` connection rather than opening its own.
  /// The caller owns the connection's lifetime, so a client built this
  /// way is BORROWED: [dispose] is a no-op and will NOT tear down a
  /// connection it did not create (lenny-wisp-0go2a.3).
  factory VmServiceClient.fromVmService(VmService vm, String isolateId) {
    return VmServiceClient._(vm, isolateId);
  }

  /// Test-only alias for [fromVmService]. Retained so existing tests
  /// compile unchanged; new code should use [fromVmService]. Pass
  /// `ownsConnection: true` to exercise the owning ([connect]) path.
  @visibleForTesting
  factory VmServiceClient.forTest(
    VmService vm,
    String isolateId, {
    bool ownsConnection = false,
  }) {
    return VmServiceClient._(vm, isolateId, ownsConnection: ownsConnection);
  }

  final VmService _vm;
  final String _isolateId;

  /// Whether this client created [_vm] (via [connect]) and therefore owns
  /// its lifetime. Borrowed connections ([fromVmService]) set this false
  /// so [dispose] never tears down a shared connection (e.g. DevTools'
  /// `serviceManager.service`).
  final bool _ownsConnection;

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
        'LeonardBinding to a target isolate.',
      );
    }
    final String? id = isolates.first.id;
    if (id == null) {
      throw StateError('First isolate has no id.');
    }
    return VmServiceClient._(vm, id, ownsConnection: true);
  }

  /// Exchange the `ext.exploration.core.handshake` contract
  /// version and active plugin manifest.
  ///
  /// Throws [BindingNotInitializedError] when the extension is absent
  /// (RPC error code `-32601`, "method not found").
  Future<HandshakeResult> handshake() async {
    final Map<String, dynamic> json = await _safeCall(
      _extHandshake,
      const <String, dynamic>{},
    );
    final Object? rawVersion =
        json['protocolVersion'] ?? json['contractVersion'];
    final Object? rawExtensions = json['extensions'];
    if (rawVersion is! String) {
      throw StateError(
        'Handshake response missing or malformed protocolVersion: $rawVersion',
      );
    }
    final List<ExtensionManifestEntry> plugins = <ExtensionManifestEntry>[];
    if (rawExtensions is List) {
      for (final Object? entry in rawExtensions) {
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
          ExtensionManifestEntry(namespace: namespace, tools: toolList),
        );
      }
    }
    return HandshakeResult(contractVersion: rawVersion, plugins: plugins);
  }

  /// Invoke the per-tool VM service extension that the binding registers
  /// via `ExtensionContext.registerExtension`:
  /// `ext.exploration.<namespace>.<tool>`.
  ///
  /// [name] must be the fully-qualified `<namespace>.<tool>` token that
  /// `buildExtensionTools` emits and `LoopHost.executeAction` documents
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
    final String ext = 'ext.exploration.$namespace.$tool';
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
  ) => _safeCall(extension, args);

  /// Dispose the VM-service connection — but ONLY if this client created
  /// it (via [connect]). A client built from a BORROWED connection
  /// ([fromVmService], e.g. DevTools' shared `serviceManager.service`)
  /// must not tear down a connection it does not own, so dispose is a
  /// no-op there. This is what stops a DevTools session teardown from
  /// killing the panel's live link to the app (lenny-wisp-0go2a.3).
  Future<void> dispose() =>
      _ownsConnection ? _vm.dispose() : Future<void>.value();

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
