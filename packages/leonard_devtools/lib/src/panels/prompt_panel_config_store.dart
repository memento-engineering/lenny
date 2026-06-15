library;

import 'dart:convert';

import 'prompt_panel_config.dart';

/// Persistence for last-used [PromptPanelConfig].
abstract class PromptPanelConfigStore {
  /// Loads and reconciles the persisted config against [liveNamespaces].
  /// Returns null when nothing is stored yet.
  Future<PromptPanelConfig?> load({required Set<String> liveNamespaces});

  /// Persists [config]. [knownNamespaces] is every namespace visible in
  /// the live manifest at save time — used to distinguish "disabled" from
  /// "newly added" on the next load.
  Future<void> save(
    PromptPanelConfig config, {
    required Set<String> knownNamespaces,
  });
}

/// In-memory store — tests and the empty default.
class InMemoryPromptPanelConfigStore implements PromptPanelConfigStore {
  Map<String, dynamic>? _cell;

  @override
  Future<PromptPanelConfig?> load({required Set<String> liveNamespaces}) async {
    if (_cell == null) return null;
    return _reconcile(_cell!, liveNamespaces);
  }

  @override
  Future<void> save(
    PromptPanelConfig config, {
    required Set<String> knownNamespaces,
  }) async {
    _cell = <String, dynamic>{
      ...config.toJson(),
      'knownExtensionNamespaces': knownNamespaces.toList(),
    };
  }
}

/// DTD-backed store. Persists via raw read/write callbacks (same seam as
/// [DtdProviderConfigStore]) so the surface is testable without a daemon.
/// Falls back to [localRead]/[localWrite] (window.localStorage in production)
/// when the DTD [read] callback returns null — covers the case where DTD is
/// not yet connected.
class DtdPromptPanelConfigStore implements PromptPanelConfigStore {
  DtdPromptPanelConfigStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    String? Function(String key)? localRead,
    void Function(String key, String value)? localWrite,
  })  : _read = read,
        _write = write,
        _localRead = localRead,
        _localWrite = localWrite;

  static const String _storageKey = 'lenny.promptConfig.lastUsed';

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final String? Function(String key)? _localRead;
  final void Function(String key, String value)? _localWrite;

  @override
  Future<PromptPanelConfig?> load({required Set<String> liveNamespaces}) async {
    String? raw = await _read(_storageKey);
    raw ??= _localRead?.call(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return _reconcile(json, liveNamespaces);
    } catch (_) {
      return null; // stale/corrupt JSON — start fresh
    }
  }

  @override
  Future<void> save(
    PromptPanelConfig config, {
    required Set<String> knownNamespaces,
  }) async {
    final encoded = jsonEncode(<String, dynamic>{
      ...config.toJson(),
      'knownExtensionNamespaces': knownNamespaces.toList(),
    });
    await _write(_storageKey, encoded);
    _localWrite?.call(_storageKey, encoded);
  }
}

/// Reconciles a deserialized JSON blob against the live manifest.
/// - ns in live but NOT in known → newly added plugin → enabled.
/// - ns in both live and known → restore persisted enabled/disabled state.
/// - ns NOT in live → drop silently.
PromptPanelConfig _reconcile(
  Map<String, dynamic> json,
  Set<String> liveNamespaces,
) {
  final cfg = PromptPanelConfig.fromJson(json);
  final known = Set<String>.from(
    (json['knownExtensionNamespaces'] as List<dynamic>?) ?? const <dynamic>[],
  );
  final enabled = cfg.enabledExtensionNamespaces;
  final reconciled = <String>{
    for (final ns in liveNamespaces)
      if (!known.contains(ns) || enabled.contains(ns)) ns,
  };
  return PromptPanelConfig(
    goal: cfg.goal,
    modelId: cfg.modelId,
    maxTurns: cfg.maxTurns,
    wallClockBudget: cfg.wallClockBudget,
    enabledExtensionNamespaces: reconciled,
  );
}
