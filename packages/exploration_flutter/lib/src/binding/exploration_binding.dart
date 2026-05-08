import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show ErrorCallback, PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../contract/plugin.dart';
import '../contract/registry.dart';
import '../diagnostics/interactive_semantics_auditor.dart';
import '../diagnostics/interactive_semantics_warning.dart';
import '../errors/error_ring_buffer.dart';
import '../screenshot_extension.dart';
import '../semantics/semantics_capture.dart';
import '../stability/frame_stability_tracker.dart';

/// Reserved prefix. Format:
/// `ext.flutter.exploration.<core_or_plugin_namespace>.<suffix>`.
/// `core` is reserved for host-owned extensions.
const String kExplorationExtensionPrefix = 'ext.flutter.exploration';

/// Default capacity of the runtime error ring buffer (PRD §6.1).
const int kDefaultErrorBufferCapacity = 50;

/// Signature of the callback we hand to `developer.registerExtension`.
typedef _ExtCallback = Future<developer.ServiceExtensionResponse> Function(
    String method, Map<String, String> parameters);

/// Override hook for the diagnostics walker root, used by tests to inject
/// a throwing root and assert the binding degrades gracefully.
@visibleForTesting
typedef DiagnosticsRootProvider = Element? Function();

class ExplorationBinding extends WidgetsFlutterBinding
    with FrameStabilityTracker {
  ExplorationBinding._(
    this._plugins,
    this._extraInteractiveTypes,
    this._errorBufferCapacity,
  );

  static ExplorationBinding? _instance;
  final List<ExplorationPlugin> _plugins;
  final List<String> _extraInteractiveTypes;

  /// Configured ring-buffer capacity. Read by [debugErrorBufferCapacity].
  final int _errorBufferCapacity;
  final SemanticsCapture _semanticsCapture = SemanticsCapture();

  /// Local registry of every extension this binding registered with the
  /// VM service, keyed by the full extension name. Powers the test-only
  /// [invokeServiceExtension] helper without re-entering the VM service.
  final Map<String, _ExtCallback> _extensionCallbacks =
      <String, _ExtCallback>{};

  /// Cache for the connect-time diagnostics walk. The walk runs at most
  /// once per binding lifetime; subsequent extension calls return the
  /// cached results.
  List<InteractiveSemanticsWarning>? _cachedDiagnostics;

  /// Test-only override of the widget-tree root used by the diagnostics
  /// walker. When null, falls back to `WidgetsBinding.instance.rootElement`.
  DiagnosticsRootProvider? _diagnosticsRootProviderForTesting;

  /// Wired in [ensureInitialized]; owns plugin lifecycle dispatch and the
  /// per-plugin error-handler chain.
  late final PluginRegistry _pluginRegistry;

  /// Bounded ring buffer of recent runtime errors (cx6.9).
  late final ErrorRingBuffer _errors;

  /// Session-start anchor used to compute `wallClockOffsetMs` for error
  /// entries. Started in [ensureInitialized].
  late final Stopwatch _sessionClock;

  /// Captured prior `FlutterError.onError`, restored by [debugReset].
  FlutterExceptionHandler? _priorFlutterOnError;

  /// Captured prior `PlatformDispatcher.onError`, restored by [debugReset].
  ErrorCallback? _priorPlatformOnError;

  /// True once [_installErrorHooks] has run for this binding instance. The
  /// `_instance == null` short-circuit in [ensureInitialized] already
  /// prevents re-hooking; this flag is a defence-in-depth guard.
  bool _errorHooksInstalled = false;

  /// User-supplied list, registration order preserved. cx6.3 reads it.
  List<ExplorationPlugin> get plugins => List.unmodifiable(_plugins);

  /// The wired plugin registry. Plugins are registered in the order they
  /// appear in the `plugins` argument to [ensureInitialized]; downstream
  /// beads (cx6.6 core action tools, cx6.8 stable observation) dispatch
  /// through this registry.
  PluginRegistry get pluginRegistry => _pluginRegistry;

  /// No-op (returns null) outside debug/profile.
  /// Throws [StateError] if a different `WidgetsBinding` is active.
  /// Idempotent: second call returns the same instance and does NOT
  /// re-install error hooks or re-register plugins.
  static ExplorationBinding? ensureInitialized({
    required List<ExplorationPlugin> plugins,
    List<String> extraInteractiveTypes = const <String>[],
    int errorBufferCapacity = kDefaultErrorBufferCapacity,
  }) {
    if (!kDebugMode && !kProfileMode) return null;
    if (_instance != null) return _instance;
    assert(errorBufferCapacity > 0,
        'errorBufferCapacity must be > 0 (got $errorBufferCapacity)');
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
    final ExplorationBinding binding = ExplorationBinding._(
      List.of(plugins),
      List<String>.unmodifiable(extraInteractiveTypes),
      errorBufferCapacity,
    );
    // The superclass `WidgetsFlutterBinding.ensureInitialized()` invocation
    // (implicit in `extends WidgetsFlutterBinding`) installs Flutter's
    // default `FlutterError.onError`. We capture priors AFTER our binding
    // has booted so the chain forwards into the framework default.
    binding._sessionClock = Stopwatch()..start();
    binding._errors = ErrorRingBuffer(
      capacity: errorBufferCapacity,
      sessionClock: binding._sessionClock,
    );
    binding._pluginRegistry = PluginRegistry(scheduler: binding);
    // Register each unique plugin namespace into the registry. The
    // legacy `plugins` getter preserves the verbatim list (including
    // duplicates) per cx6.2's contract, but the registry enforces
    // namespace uniqueness — duplicate registrations are logged and
    // skipped so lifecycle dispatch sees each plugin exactly once.
    for (final ExplorationPlugin p in binding._plugins) {
      try {
        binding._pluginRegistry.register(p);
      } on StateError catch (e) {
        debugPrint(
          '[exploration] skipping plugin ${p.namespace}: $e',
        );
      } on ArgumentError catch (e) {
        debugPrint(
          '[exploration] skipping plugin ${p.namespace}: $e',
        );
      }
    }
    _instance = binding;
    binding._installErrorHooks();
    binding._registerCoreExtensions();
    binding._registerDiagnosticsExtension();
    // Run plugin initialization in a microtask so it completes before the
    // first frame without blocking ensureInitialized's synchronous return.
    scheduleMicrotask(() => binding._pluginRegistry.initializeAll());
    return binding;
  }

  /// Singleton accessor. Returns the active binding; throws [StateError]
  /// if [ensureInitialized] has not been called (or returned null).
  static ExplorationBinding get instance {
    final ExplorationBinding? b = _instance;
    if (b == null) {
      throw StateError(
        'ExplorationBinding has not been initialized. Call '
        'ExplorationBinding.ensureInitialized(...) first.',
      );
    }
    return b;
  }

  void _installErrorHooks() {
    if (_errorHooksInstalled) return;
    _errorHooksInstalled = true;
    _priorFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _errors.add(details.exceptionAsString(), details.stack);
      // Plugin handler chain — return value intentionally ignored: the ring
      // buffer always records, and we always forward to the prior handler
      // so framework default behaviour (e.g. dumping to console) survives.
      _pluginRegistry.dispatchError(details);
      _priorFlutterOnError?.call(details);
    };
    _priorPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _errors.add(error.toString(), stack);
      final FlutterErrorDetails details =
          FlutterErrorDetails(exception: error, stack: stack);
      _pluginRegistry.dispatchError(details);
      // If a prior handler exists we forward to it; otherwise we report
      // "handled" (matches the framework's null-onError default of true).
      return _priorPlatformOnError?.call(error, stack) ?? true;
    };
  }

  void _uninstallErrorHooks() {
    if (!_errorHooksInstalled) return;
    FlutterError.onError = _priorFlutterOnError;
    PlatformDispatcher.instance.onError = _priorPlatformOnError;
    _priorFlutterOnError = null;
    _priorPlatformOnError = null;
    _errorHooksInstalled = false;
  }

  void _registerCoreExtensions() {
    _registerExtension(
      '$kExplorationExtensionPrefix.core.handshake',
      (String method, Map<String, String> parameters) async {
        return developer.ServiceExtensionResponse.result(
          '{"protocolVersion":"1",'
          '"bindingType":"ExplorationBinding",'
          '"flutterMode":"${kDebugMode ? 'debug' : 'profile'}",'
          '"pluginCount":${_plugins.length}}',
        );
      },
    );
    _registerExtension(
      '$kExplorationExtensionPrefix.core.get_semantics',
      (String method, Map<String, String> parameters) async {
        final List<Map<String, Object>> recs = _semanticsCapture.capture();
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object>{
            'semantics': recs,
            'count': recs.length,
          }),
        );
      },
    );
    _registerExtension(
      '$kExplorationExtensionPrefix.core.get_recent_errors',
      (String method, Map<String, String> parameters) async {
        final int since = int.tryParse(parameters['since'] ?? '0') ?? 0;
        final List<ErrorEntry> entries = _errors.entriesSince(since);
        return developer.ServiceExtensionResponse.result(jsonEncode(
          <String, Object?>{
            'entries': entries
                .map((ErrorEntry e) => e.toJson())
                .toList(growable: false),
            'cursor':
                entries.isEmpty ? since : _errors.highestSeq,
          },
        ));
      },
    );
    if (kDebugMode || kProfileMode) {
      developer.registerExtension(
        '$kExplorationExtensionPrefix.core.screenshot',
        (String method, Map<String, String> params) async {
          try {
            final ScreenshotResult result = await captureScreenshot(this);
            return developer.ServiceExtensionResponse.result(
              jsonEncode(<String, dynamic>{'result': result.toJson()}),
            );
          } on ScreenshotUnavailable catch (e) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionError,
              jsonEncode(<String, dynamic>{
                'code': 1,
                'message': e.reason,
              }),
            );
          }
        },
      );
    }
  }

  void _registerDiagnosticsExtension() {
    if (!kDebugMode && !kProfileMode) return;
    _registerExtension(
      '$kExplorationExtensionPrefix.core.diagnostics_warnings',
      (String method, Map<String, String> parameters) async {
        try {
          _cachedDiagnostics ??= _runDiagnostic();
          return developer.ServiceExtensionResponse.result(jsonEncode(
            <String, Object?>{
              'ok': true,
              'results': _cachedDiagnostics!
                  .map((InteractiveSemanticsWarning w) => w.toJson())
                  .toList(),
            },
          ));
        } catch (e, st) {
          debugPrint('exploration: diagnostics walk failed: $e\n$st');
          return developer.ServiceExtensionResponse.result(jsonEncode(
            <String, Object?>{
              'ok': false,
              'error': e.toString(),
              'results': const <Object?>[],
            },
          ));
        }
      },
    );
  }

  List<InteractiveSemanticsWarning> _runDiagnostic() {
    final Element? root = _diagnosticsRootProviderForTesting != null
        ? _diagnosticsRootProviderForTesting!()
        : WidgetsBinding.instance.rootElement;
    if (root == null) return const <InteractiveSemanticsWarning>[];
    return InteractiveSemanticsAuditor(
      extraInteractiveTypes: _extraInteractiveTypes,
    ).audit(root);
  }

  /// Registers [callback] both with `dart:developer` and in our local
  /// registry so [invokeServiceExtension] can dispatch without going
  /// through the VM service.
  void _registerExtension(String name, _ExtCallback callback) {
    developer.registerExtension(name, callback);
    _extensionCallbacks[name] = callback;
  }

  /// Test-only: dispatch to a registered extension's callback and return
  /// the JSON-encoded result. Mirrors what a remote VM service caller
  /// would receive but stays in-process.
  @visibleForTesting
  Future<String> invokeServiceExtension(
      String name, Map<String, String> args) async {
    final _ExtCallback? cb = _extensionCallbacks[name];
    if (cb == null) {
      throw StateError('No extension registered with name "$name".');
    }
    final developer.ServiceExtensionResponse resp = await cb(name, args);
    return resp.result ?? '';
  }

  /// Test-only: install a custom root provider for the diagnostics walker.
  /// Pass null to restore the live `rootElement` lookup.
  @visibleForTesting
  void debugSetDiagnosticsRootProviderForTesting(
      DiagnosticsRootProvider? provider) {
    _diagnosticsRootProviderForTesting = provider;
    _cachedDiagnostics = null;
  }

  /// Test-only: returns true iff the named extension was registered with
  /// this binding (and thus, via [_registerExtension], with the VM
  /// service). Used to assert release-mode gating.
  @visibleForTesting
  bool debugHasRegisteredExtension(String name) =>
      _extensionCallbacks.containsKey(name);

  /// Test-only: append a synthetic error entry directly to the ring
  /// without going through `FlutterError.reportError`. Useful for tests
  /// that need to drive the ring without tripping the framework's
  /// failure surface.
  @visibleForTesting
  void debugAppendError(String message, StackTrace? stack) {
    _errors.add(message, stack);
  }

  /// Test-only: read the current ring contents.
  @visibleForTesting
  List<ErrorEntry> debugErrorEntries() => _errors.entries;

  /// Test-only: highest seq currently observed by the ring.
  @visibleForTesting
  int debugHighestErrorSeq() => _errors.highestSeq;

  /// Test-only: are the wrapped error hooks currently installed?
  @visibleForTesting
  bool debugErrorHooksInstalled() => _errorHooksInstalled;

  /// Test-only: configured error-buffer capacity.
  @visibleForTesting
  int debugErrorBufferCapacity() => _errorBufferCapacity;

  /// Test-only: prior FlutterError.onError captured at install time.
  @visibleForTesting
  FlutterExceptionHandler? debugPriorFlutterOnError() => _priorFlutterOnError;

  /// Test-only: prior PlatformDispatcher.onError captured at install time.
  @visibleForTesting
  ErrorCallback? debugPriorPlatformOnError() => _priorPlatformOnError;

  /// Test-only: clears the singleton AND restores the captured prior
  /// `FlutterError.onError` / `PlatformDispatcher.onError` so the next
  /// `ensureInitialized` call starts from a clean slate.
  @visibleForTesting
  static void debugReset() {
    final ExplorationBinding? b = _instance;
    if (b != null) {
      b._uninstallErrorHooks();
    }
    _instance = null;
  }

  /// Test-only alias: clears the singleton so tests that call
  /// `ensureInitialized` can isolate setup. Intentionally identical to
  /// [debugReset] — keeps the published name consistent with the bead
  /// spec.
  @visibleForTesting
  static void resetForTesting() => debugReset();

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
