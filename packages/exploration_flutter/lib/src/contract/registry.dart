import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'perception_plugin.dart';
import 'plugin.dart';
import 'plugin_context.dart';
import 'types.dart';

/// Per-method discriminator used by the exception-isolation guard.
enum _Method { observe, busyState, onActionExecuted }

/// Internal bookkeeping wrapper around a registered plugin.
class _Entry {
  _Entry(this.plugin, this.context);

  final ExplorationPlugin plugin;
  final PluginContext context;

  /// Set when [ExplorationPlugin.initialize] threw. Short-circuits every
  /// subsequent dispatch (PRD §17).
  bool initFailed = false;

  /// Consecutive failure counter, per dispatched method.
  final Map<_Method, int> failures = <_Method, int>{
    _Method.observe: 0,
    _Method.busyState: 0,
    _Method.onActionExecuted: 0,
  };

  /// Auto-disable flag, per dispatched method. Once `true`, the
  /// corresponding method is never dispatched again for this session.
  final Map<_Method, bool> disabled = <_Method, bool>{
    _Method.observe: false,
    _Method.busyState: false,
    _Method.onActionExecuted: false,
  };
}

/// Registry that owns plugin lifecycle dispatch for the host binding.
///
/// Enforces:
/// - namespace shape (`^[a-z][a-z0-9_]*$`) and uniqueness,
/// - mandatory `<namespace>.<tool>` prefixing and bare-token tool names,
/// - registration-order preservation across every dispatch,
/// - per-method exception isolation with 3-strikes auto-disable
///   (PRD §17),
/// - per-plugin error-handler chaining (`registerErrorHandler`).
class PluginRegistry {
  PluginRegistry({required SchedulerBinding scheduler})
      : _scheduler = scheduler;

  final SchedulerBinding _scheduler;
  final List<_Entry> _entries = <_Entry>[];
  bool _finalized = false;
  static final RegExp _nsRe = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Plugin namespaces in registration order (post de-duplication).
  ///
  /// Read by cx6.8's stable-observation primitive to map per-plugin
  /// observation fragments back to their owning plugin and to enforce
  /// per-plugin budget overrides.
  List<String> get namespaces => List<String>.unmodifiable(<String>[
        for (final _Entry e in _entries) e.plugin.namespace,
      ]);

  /// Plugin manifest: ordered `(namespace, bare tool names)` records,
  /// one per registered plugin (post de-duplication). Read by the
  /// binding's `core.handshake` extension to build the handshake
  /// `plugins` array. Does not finalize the registry.
  List<({String namespace, List<String> tools})> get manifest =>
      List<({String namespace, List<String> tools})>.unmodifiable(
        <({String namespace, List<String> tools})>[
          for (final _Entry e in _entries)
            (
              namespace: e.plugin.namespace,
              tools: List<String>.unmodifiable(
                e.plugin.tools.map((ExplorationTool t) => t.name),
              ),
            ),
        ],
      );

  /// Returns true iff the registered plugin for [namespace] mixes in
  /// [PerceptionPlugin]. Returns false for unknown namespaces.
  bool isPerceptionNative(String namespace) {
    for (final _Entry e in _entries) {
      if (e.plugin.namespace == namespace) return e.plugin is PerceptionPlugin;
    }
    return false;
  }

  /// All registered plugins that mix in [PerceptionPlugin], in
  /// registration order.
  List<ExplorationPlugin> get perceptionNativePlugins =>
      List<ExplorationPlugin>.unmodifiable(<ExplorationPlugin>[
        for (final _Entry e in _entries)
          if (e.plugin is PerceptionPlugin) e.plugin,
      ]);

  /// Register [p]. Order is preserved across every dispatch.
  ///
  /// Throws [StateError] if [mergedTools]/[finalize] has already run.
  /// Throws [ArgumentError] if the namespace fails the `^[a-z][a-z0-9_]*$`
  /// regex. Throws [StateError] on a duplicate namespace.
  void register(ExplorationPlugin p) {
    if (_finalized) {
      throw StateError('PluginRegistry already finalized');
    }
    if (!_nsRe.hasMatch(p.namespace)) {
      throw ArgumentError.value(
        p.namespace,
        'namespace',
        r'must match ^[a-z][a-z0-9_]*$',
      );
    }
    for (final e in _entries) {
      if (e.plugin.namespace == p.namespace) {
        throw StateError('duplicate plugin namespace: ${p.namespace}');
      }
    }
    _entries.add(
      _Entry(p, PluginContext(namespace: p.namespace, scheduler: _scheduler)),
    );
  }

  /// Compute the merged tool list keyed by fully-qualified name.
  ///
  /// Tool names must be bare tokens (no `.`); the registry prefixes each
  /// with the owning plugin's namespace. Throws [ArgumentError] for a
  /// dotted tool name and [StateError] for a collision (intra- or
  /// inter-plugin).
  Map<String, ExplorationTool> mergedTools() {
    final out = <String, ExplorationTool>{};
    for (final e in _entries) {
      for (final t in e.plugin.tools) {
        if (t.name.contains('.')) {
          throw ArgumentError.value(
            t.name,
            'tool.name',
            'must be bare token (no ".")',
          );
        }
        final fq = '${e.plugin.namespace}.${t.name}';
        if (out.containsKey(fq)) {
          throw StateError('tool name collision: $fq');
        }
        out[fq] = t;
      }
    }
    _finalized = true;
    return Map.unmodifiable(out);
  }

  /// Alias for [mergedTools].
  Map<String, ExplorationTool> finalize() => mergedTools();

  /// Call [ExplorationPlugin.initialize] on every registered plugin in
  /// registration order. Failures are logged and mark the plugin as
  /// failed; the call never rethrows.
  Future<void> initializeAll() async {
    for (final e in _entries) {
      try {
        await e.plugin.initialize(e.context);
      } catch (err, st) {
        e.initFailed = true;
        debugPrint(
          '[exploration] plugin ${e.plugin.namespace} initialize failed: '
          '$err\n$st',
        );
      }
    }
  }

  /// Dispatch [observe] across every (non-disabled) plugin in
  /// registration order, returning the merged fragment map keyed by
  /// plugin namespace. Plugins returning `null` are omitted.
  Future<Map<String, Map<String, Object?>>> observeAll(
    ObservationContext ctx,
  ) async {
    final out = <String, Map<String, Object?>>{};
    for (final e in _entries) {
      final fragment = await _guard<Map<String, Object?>?>(
        e,
        _Method.observe,
        () => e.plugin.observe(ctx),
        null,
      );
      if (fragment != null) {
        out[e.plugin.namespace] = fragment;
      }
    }
    return out;
  }

  /// Dispatch [busyState] across every (non-disabled) plugin in
  /// registration order. Failures yield [BusyState.idle] for the
  /// affected plugin.
  Future<List<MapEntry<String, BusyState>>> busyStateAll() async {
    final out = <MapEntry<String, BusyState>>[];
    for (final e in _entries) {
      final state = await _guard<BusyState>(
        e,
        _Method.busyState,
        () => e.plugin.busyState(),
        BusyState.idle,
      );
      out.add(MapEntry(e.plugin.namespace, state));
    }
    return out;
  }

  /// Dispatch [onActionExecuted] across every (non-disabled) plugin in
  /// registration order.
  Future<void> onActionExecutedAll(ExecutedAction action) async {
    for (final e in _entries) {
      await _guard<void>(
        e,
        _Method.onActionExecuted,
        () => e.plugin.onActionExecuted(action),
        null,
      );
    }
  }

  /// Call [ExplorationPlugin.dispose] on every registered plugin in
  /// registration order. Each call is exception-isolated; every plugin
  /// is disposed even if earlier ones throw.
  Future<void> disposeAll() async {
    for (final e in _entries) {
      try {
        await e.plugin.dispose();
      } catch (err, st) {
        debugPrint(
          '[exploration] plugin ${e.plugin.namespace} dispose threw: '
          '$err\n$st',
        );
      }
    }
  }

  /// Dispatch [details] through every plugin's error-handler chain in
  /// registration order. The first handler that returns `true` claims
  /// the error and short-circuits further dispatch. Plugins flagged
  /// [initFailed] are skipped. Per-handler exceptions are logged and
  /// treated as not claiming.
  bool dispatchError(FlutterErrorDetails details) {
    for (final e in _entries) {
      if (e.initFailed) continue;
      for (final h in e.context.errorHandlers) {
        bool claimed;
        try {
          claimed = h(details);
        } catch (err, st) {
          debugPrint(
            '[exploration] plugin ${e.plugin.namespace} error handler '
            'threw: $err\n$st',
          );
          claimed = false;
        }
        if (claimed) return true;
      }
    }
    return false;
  }

  /// Run [body] under the per-method exception-isolation guard. Returns
  /// [fallback] when the entry is `initFailed`/method-disabled or when
  /// [body] throws. Tracks consecutive failures and emits a single
  /// auto-disable log line when the third consecutive failure occurs.
  Future<R> _guard<R>(
    _Entry e,
    _Method m,
    Future<R> Function() body,
    R fallback,
  ) async {
    if (e.initFailed || e.disabled[m]!) return fallback;
    try {
      final r = await body();
      e.failures[m] = 0;
      return r;
    } catch (err, st) {
      final next = e.failures[m]! + 1;
      e.failures[m] = next;
      debugPrint(
        '[exploration] plugin ${e.plugin.namespace} ${m.name} threw: '
        '$err\n$st',
      );
      if (next >= 3 && !e.disabled[m]!) {
        e.disabled[m] = true;
        debugPrint(
          '[exploration] plugin ${e.plugin.namespace} auto-disabled after '
          '3 failures in ${m.name}',
        );
      }
      return fallback;
    }
  }
}
