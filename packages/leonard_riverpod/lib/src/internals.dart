import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider id derivation: `provider.name` when present and non-empty,
/// else the provider's runtimeType. Mirrors PRD §6.4 — the
/// label-or-type identifier surfaced to the agent.
String providerIdOf(ProviderBase<Object?> p) {
  final l = p.name;
  return (l != null && l.isNotEmpty) ? l : p.runtimeType.toString();
}

/// One entry in the `recent_state_changes` ring buffer.
class StateChange {
  const StateChange({required this.providerId, required this.atTurn});

  final String providerId;
  final int atTurn;

  Map<String, Object?> toJson() => <String, Object?>{
    'provider_id': providerId,
    'at_turn': atTurn,
  };
}

/// Simple fixed-capacity FIFO ring used for [StateChange] history.
class _Ring<T> {
  _Ring(this.cap);

  final int cap;
  final List<T> _xs = <T>[];

  void add(T x) {
    _xs.add(x);
    if (_xs.length > cap) _xs.removeAt(0);
  }

  List<T> snapshot() => List<T>.unmodifiable(_xs);

  void clear() => _xs.clear();
}

/// `ProviderObserver` that tracks live providers in a container and
/// records the most-recent updates as a fixed-capacity ring buffer.
///
/// Hosts MUST install this on their `ProviderContainer(observers: [...])`
/// for the plugin to surface anything via its perception fragment.
class LeonardProviderObserver extends ProviderObserver {
  LeonardProviderObserver({int ringCapacity = 16})
    : _changes = _Ring<StateChange>(ringCapacity);

  final Map<String, ProviderBase<Object?>> _live =
      <String, ProviderBase<Object?>>{};
  final _Ring<StateChange> _changes;
  final List<String> _pending = <String>[];

  /// Read-only view of currently-live providers, keyed by provider id.
  Map<String, ProviderBase<Object?>> get live =>
      Map<String, ProviderBase<Object?>>.unmodifiable(_live);

  /// Drain provider-update notifications recorded since the last call,
  /// stamping each with [atTurn] and appending into the ring buffer.
  /// Called by the plugin from `prepareForObservation()` (production
  /// stamps turn 0) before each perception build reads the ring.
  void flushPendingAt(int atTurn) {
    for (final id in _pending) {
      _changes.add(StateChange(providerId: id, atTurn: atTurn));
    }
    _pending.clear();
  }

  /// Snapshot (oldest-first) of recent state changes.
  List<StateChange> recentChanges() => _changes.snapshot();

  /// Reset all internal tracking.
  void clear() {
    _live.clear();
    _changes.clear();
    _pending.clear();
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _live[providerIdOf(provider)] = provider;
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    _live.remove(providerIdOf(provider));
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _pending.add(providerIdOf(provider));
  }
}
