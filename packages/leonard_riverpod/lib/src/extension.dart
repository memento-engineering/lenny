import 'package:leonard_flutter/contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genesis_perception/genesis_perception.dart';

import 'internals.dart';
import 'riverpod_perception.dart';

class _InvalidateTool extends LeonardTool {
  _InvalidateTool(this._c, this._o);

  final ProviderContainer _c;
  final LeonardProviderObserver _o;

  @override
  String get name => 'invalidate_provider';

  @override
  String get description =>
      'Force-refresh a Riverpod provider. provider_id is the provider name '
      'when set, otherwise the provider runtimeType, as surfaced in the '
      'riverpod observation fragment under invalidatable_providers.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['provider_id'],
        'properties': <String, Object?>{
          'provider_id': <String, Object?>{'type': 'string'},
        },
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final id = args['provider_id'];
    if (id is! String) {
      return const ToolResult(
        ok: false,
        error: 'provider_id (string) required',
      );
    }
    final p = _o.live[id];
    if (p == null) {
      return ToolResult(ok: false, error: 'unknown provider_id: $id');
    }
    _c.invalidate(p);
    return const ToolResult(ok: true);
  }
}

/// Reference Riverpod plugin for the Flutter Exploration Agent.
///
/// Hosts MUST construct a `ProviderContainer` with this plugin's
/// [observer] installed (`ProviderContainer(observers: [plugin.observer])`)
/// AND pass that same container to this constructor; otherwise the
/// plugin will report no providers and `invalidate_provider` will be a
/// no-op.
class RiverpodLeonardExtension extends LeonardExtension with PerceptionExtension {
  RiverpodLeonardExtension({
    required ProviderContainer container,
    LeonardProviderObserver? observer,
  })  : _c = container,
        _o = observer ?? LeonardProviderObserver();

  final ProviderContainer _c;
  final LeonardProviderObserver _o;
  bool _initialized = false;
  late final _InvalidateTool _tool = _InvalidateTool(_c, _o);

  /// The observer this plugin uses to track providers; hosts include it
  /// in their `ProviderContainer(observers: [...])`.
  LeonardProviderObserver get observer => _o;

  @override
  String get namespace => 'riverpod';

  @override
  List<LeonardTool> get tools => <LeonardTool>[_tool];

  @override
  Future<void> initialize(ExtensionContext c) async {
    _initialized = true;
  }

  /// Pre-build side-effect seam (relocated from the retired `observe()`):
  /// drain the observer's pending updates into the change ring before the
  /// idle check and build read it. Production always stamped turn 0.
  @override
  void prepareForObservation() {
    if (_initialized) _o.flushPendingAt(0);
  }

  /// Reproduces the retired `observe() == null` suppression. Evaluated by
  /// the binding AFTER [prepareForObservation], so `recentChanges()`
  /// already reflects the just-flushed pending updates — matching the old
  /// flush-then-null-gate ordering.
  @override
  bool isPerceptionIdle() =>
      !_initialized || (_o.live.isEmpty && _o.recentChanges().isEmpty);

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction a) async {}

  @override
  Future<void> dispose() async {
    _initialized = false;
    _o.clear();
  }

  @override
  Seed buildPerception() => RiverpodPerception(_o);
}
