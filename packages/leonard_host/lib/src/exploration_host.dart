import 'dart:convert';
import 'dart:developer' as developer;

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';

/// Hosts a set of [LeonardExtension]s over the VM service so an external
/// driver (`leonard_cli` / `leonard_drive`) can perceive and act on a
/// non-Flutter Dart program.
///
/// This is the non-Flutter peer of `leonard_flutter`'s `LeonardBinding`:
/// both register the identical `ext.exploration.*` contract, but a plain
/// Dart program has no widget tree, so the host omits the Flutter-only core
/// fragment (semantics / routes / screenshot). Each registered
/// `PerceptionExtension` contributes its `extensions.<namespace>` fragment,
/// which is the whole observation for a non-Flutter target.
///
/// Registers, via `dart:developer`:
///   * `ext.exploration.core.handshake` — protocol version + tool manifest
///   * `ext.exploration.core.get_stable_observation` —
///     `{type: Observation, value: {extensions: {ns: fragment}}}`
///   * `ext.exploration.{ns}.{tool}` — `dispatchToolToEnvelope` per tool
///
/// The hosting program must run with the VM service enabled (e.g.
/// `dart run --enable-vm-service`); the driver connects to the printed
/// `ws://…/ws` URI.
class ExplorationHost {
  /// Builds a host over [extensions]. Tools and observation fragments are
  /// gathered lazily on first use (or in [install]); construct with every
  /// extension up front.
  ExplorationHost({
    required List<LeonardExtension> extensions,
    String protocolVersion = '2',
    void Function(String message)? logger,
  }) : _protocolVersion = protocolVersion,
       _log = logger ?? _noop,
       _registry = ExtensionRegistry(logger: logger) {
    for (final LeonardExtension e in extensions) {
      _registry.register(e);
    }
  }

  static const String _prefix = 'ext.exploration';

  final String _protocolVersion;
  final void Function(String) _log;
  final ExtensionRegistry _registry;
  Map<String, LeonardTool>? _tools;

  static void _noop(String _) {}

  /// Initialize extensions, finalize the tool set, then register every
  /// `ext.exploration.*` VM-service extension. Call once, after the VM
  /// service is up.
  Future<void> install() async {
    final Map<String, LeonardTool> tools = await _prepare();

    developer.registerExtension('$_prefix.core.handshake', (_, _) async {
      return developer.ServiceExtensionResponse.result(await handshakeJson());
    });
    developer.registerExtension('$_prefix.core.get_stable_observation', (
      _,
      _,
    ) async {
      return developer.ServiceExtensionResponse.result(await observationJson());
    });
    for (final MapEntry<String, LeonardTool> e in tools.entries) {
      developer.registerExtension('$_prefix.${e.key}', (_, params) async {
        return developer.ServiceExtensionResponse.result(
          await dispatchToolToEnvelope(
            e.value,
            decodeServiceExtensionParams(params),
          ),
        );
      });
    }
  }

  /// The `core.handshake` response body (JSON string): protocol version plus
  /// the `{namespace, tools}` manifest the driver lists with `tools`.
  Future<String> handshakeJson() async {
    await _prepare();
    return jsonEncode(<String, Object?>{
      'protocolVersion': _protocolVersion,
      'bindingType': 'LeonardHost',
      'extensions': <Map<String, Object?>>[
        for (final ({String namespace, List<String> tools}) m
            in _registry.manifest)
          <String, Object?>{'namespace': m.namespace, 'tools': m.tools},
      ],
      // A pure-Dart target has no widget tree, so no screenshot — but the
      // field is part of the handshake contract, so report it (empty) for
      // uniformity with the Flutter binding.
      'capabilities': const <String>[],
    });
  }

  /// The `core.get_stable_observation` response body (JSON string),
  /// `{type: Observation, value: {extensions: {<ns>: <fragment>}}}`.
  ///
  /// Mirrors the Flutter binding's single observation loop: per
  /// [PerceptionExtension], `prepareForObservation()` runs first, then the
  /// idle gate, then mount → build → serialize. A tools-only extension (no
  /// [PerceptionExtension] mixin) contributes no fragment.
  Future<String> observationJson() async {
    await _prepare();
    final Map<String, Object?> extensions = <String, Object?>{};
    for (final LeonardExtension ext in _registry.extensions) {
      if (ext is! PerceptionExtension) continue;
      final PerceptionExtension pp = ext;
      final String ns = ext.namespace;
      try {
        pp.prepareForObservation();
        if (pp.isPerceptionIdle()) continue;
        final PerceptionOwner owner = PerceptionOwner();
        final Branch root = owner.mountRoot(pp.buildPerception());
        extensions[ns] = serializePerceptionFragment(root);
        owner.unmountRoot();
      } catch (err, st) {
        _log('extension $ns threw during observation: $err\n$st');
      }
    }
    return jsonEncode(<String, Object?>{
      'type': 'Observation',
      'value': <String, Object?>{'extensions': extensions},
    });
  }

  /// Dispatch a fully-qualified tool (`<namespace>.<tool>`) with raw
  /// VM-service string [params] (each value JSON-encoded, as the driver
  /// sends them); returns the `{ok, value, error}` envelope JSON string.
  /// Throws [ArgumentError] when [fqName] is not a registered tool.
  Future<String> invokeToolJson(
    String fqName,
    Map<String, String> params,
  ) async {
    final Map<String, LeonardTool> tools = await _prepare();
    final LeonardTool? tool = tools[fqName];
    if (tool == null) {
      throw ArgumentError.value(fqName, 'fqName', 'unknown tool');
    }
    return dispatchToolToEnvelope(tool, decodeServiceExtensionParams(params));
  }

  /// Run extension `initialize` once and finalize the merged tool set.
  /// Idempotent — safe to call from every public entrypoint.
  Future<Map<String, LeonardTool>> _prepare() async {
    final Map<String, LeonardTool>? cached = _tools;
    if (cached != null) return cached;
    await _registry.initializeAll();
    return _tools = _registry.mergedTools();
  }
}
