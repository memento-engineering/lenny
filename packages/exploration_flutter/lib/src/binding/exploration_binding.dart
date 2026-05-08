import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../contract/plugin.dart';
import '../semantics/semantics_capture.dart';
import '../stability/frame_stability_tracker.dart';

/// Reserved prefix. Format:
/// `ext.flutter.exploration.<core_or_plugin_namespace>.<suffix>`.
/// `core` is reserved for host-owned extensions.
const String kExplorationExtensionPrefix = 'ext.flutter.exploration';

class ExplorationBinding extends WidgetsFlutterBinding
    with FrameStabilityTracker {
  ExplorationBinding._(this._plugins);

  static ExplorationBinding? _instance;
  final List<ExplorationPlugin> _plugins;
  final SemanticsCapture _semanticsCapture = SemanticsCapture();

  /// User-supplied list, registration order preserved. cx6.3 reads it.
  List<ExplorationPlugin> get plugins => List.unmodifiable(_plugins);

  /// No-op (returns null) outside debug/profile.
  /// Throws [StateError] if a different `WidgetsBinding` is active.
  /// Idempotent: second call returns the same instance.
  static ExplorationBinding? ensureInitialized({
    required List<ExplorationPlugin> plugins,
  }) {
    if (!kDebugMode && !kProfileMode) return null;
    if (_instance != null) return _instance;
    // BindingBase.debugBindingType() is non-null once any binding has been
    // initialized; it stays null until then. Available in debug and profile
    // (which is the only mode this method runs in), per BindingBase.
    final Type? existingType = BindingBase.debugBindingType();
    if (existingType != null && existingType != ExplorationBinding) {
      throw StateError(
        'ExplorationBinding cannot be installed: another WidgetsBinding '
        '($existingType) is already active. ExplorationBinding '
        'is incompatible with IntegrationTestWidgetsFlutterBinding and '
        'other custom bindings (PRD §6.5).',
      );
    }
    final binding = ExplorationBinding._(List.of(plugins));
    _instance = binding;
    binding._registerCoreExtensions();
    return binding;
  }

  void _registerCoreExtensions() {
    developer.registerExtension(
      '$kExplorationExtensionPrefix.core.handshake',
      (method, parameters) async {
        return developer.ServiceExtensionResponse.result(
          '{"protocolVersion":"1",'
          '"bindingType":"ExplorationBinding",'
          '"flutterMode":"${kDebugMode ? 'debug' : 'profile'}",'
          '"pluginCount":${_plugins.length}}',
        );
      },
    );
    developer.registerExtension(
      '$kExplorationExtensionPrefix.core.get_semantics',
      (method, parameters) async {
        final List<Map<String, Object>> recs = _semanticsCapture.capture();
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object>{
            'semantics': recs,
            'count': recs.length,
          }),
        );
      },
    );
  }

  @visibleForTesting
  static void debugReset() => _instance = null;

  /// Returns a `ZoneSpecification` that intercepts microtask scheduling so
  /// the binding's `pendingMicrotasks` edge signal flips immediately when
  /// the user-mode app schedules a microtask. Wrap the user `runApp` (or
  /// app entrypoint) with `runZoned(..., zoneSpecification: spec)` to
  /// install — currently consumed by integration tests; cx6.7's
  /// `installAndRun` will install it for production.
  static ZoneSpecification stabilityZoneSpec(ExplorationBinding binding) {
    return ZoneSpecification(
      scheduleMicrotask: (Zone self, ZoneDelegate parent, Zone zone,
          void Function() f) {
        binding.markMicrotaskScheduled();
        parent.scheduleMicrotask(zone, f);
      },
    );
  }
}
