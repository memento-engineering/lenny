/// Persistence layer for [ProviderConfig].
///
/// SECURITY: The store persists the FULL unredacted [ProviderConfig]
/// (including the bearer token / api key) — workspace-scoped DTD
/// state is local to the developer's machine, the same way `~/.netrc`
/// or `.env` files are. We deliberately do NOT round-trip the token
/// through a remote service. The on-disk JSON is readable by anything
/// that can read the workspace files; treat it accordingly.
library;

import 'dart:async';
import 'dart:convert';

import 'provider_config.dart';

/// Async key/value persistence keyed by `providerId`.
abstract class ProviderConfigStore {
  /// Read the config for [providerId], or `null` if none is stored.
  Future<ProviderConfig?> load(String providerId);

  /// Persist [config] under its own id. Idempotent.
  Future<void> save(ProviderConfig config);
}

/// In-memory store — tests and the empty default.
class InMemoryProviderConfigStore implements ProviderConfigStore {
  final Map<String, Map<String, dynamic>> _cells =
      <String, Map<String, dynamic>>{};

  @override
  Future<ProviderConfig?> load(String providerId) async {
    final raw = _cells[providerId];
    if (raw == null) return null;
    return ProviderConfig.fromJson(raw);
  }

  @override
  Future<void> save(ProviderConfig config) async {
    _cells[config.id] = config.toJson();
  }
}

/// DTD-backed store. Persists JSON blobs keyed by
/// `lenny.providerConfig.<providerId>` via raw read/write callbacks so
/// the same surface is testable with a fake daemon.
///
/// The callbacks mirror the shape used by `DtdTrajectorySink`:
/// `_read(key) → String?` returns `null` for missing keys, `_write`
/// overwrites.
class DtdProviderConfigStore implements ProviderConfigStore {
  DtdProviderConfigStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) : _read = read,
       _write = write;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  String _key(String providerId) => 'lenny.providerConfig.$providerId';

  @override
  Future<ProviderConfig?> load(String providerId) async {
    final raw = await _read(_key(providerId));
    if (raw == null || raw.isEmpty) return null;
    final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return ProviderConfig.fromJson(json);
  }

  @override
  Future<void> save(ProviderConfig config) async {
    await _write(_key(config.id), jsonEncode(config.toJson()));
  }
}
