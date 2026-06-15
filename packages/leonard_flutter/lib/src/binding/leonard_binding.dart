import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show ErrorCallback, PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:genesis_perception/genesis_perception.dart';
import '../contract/perception_extension.dart';
import '../contract/extension.dart';
import '../contract/registry.dart';
import '../core_tools/core_extension.dart';
import '../diagnostics/interactive_semantics_auditor.dart';
import '../diagnostics/interactive_semantics_warning.dart';
import '../errors/error_ring_buffer.dart';
import '../observation/budgeted_json.dart';
import '../observation/core_fragment.dart';
import '../observation/core_perception.dart';
import '../observation/observation_request.dart';
import '../observation/policy_loop.dart';
import '../observation/stability_metadata.dart';
import '../screenshot_extension.dart';
import '../semantics/semantics_capture.dart';
import '../stability/frame_stability_tracker.dart';
import 'leonard_app.dart';
import 'perception_serializer.dart';

/// Reserved prefix. Format:
/// `ext.exploration.<core_or_extension_namespace>.<suffix>`.
/// `core` is reserved for host-owned extensions.
const String kLeonardExtensionPrefix = 'ext.exploration';

/// Default capacity of the runtime error ring buffer (PRD §6.1).
const int kDefaultErrorBufferCapacity = 50;

/// Signature of the callback we hand to `developer.registerExtension`.
typedef _ExtCallback =
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> parameters,
    );

/// Override hook for the diagnostics walker root, used by tests to inject
/// a throwing root and assert the binding degrades gracefully.
@visibleForTesting
typedef DiagnosticsRootProvider = Element? Function();

class LeonardBinding extends WidgetsFlutterBinding with FrameStabilityTracker {
  LeonardBinding._(
    this._extensions,
    this._extraInteractiveTypes,
    this._errorBufferCapacity,
    this._installCoreExtension,
  );

  static LeonardBinding? _instance;
  final List<LeonardExtension> _extensions;
  final List<String> _extraInteractiveTypes;

  /// Configured ring-buffer capacity. Read by [debugErrorBufferCapacity].
  final int _errorBufferCapacity;

  /// When `true` (production default), [_wireExtensions] constructs and
  /// registers a host-owned [CoreExtension] FIRST, reserving the `core`
  /// namespace before any user extensions are registered. Test harnesses
  /// that need to stand in their own `core` extension (the dogfood loop —
  /// see lenny-cx6.45) set this to `false` via the `@visibleForTesting`
  /// param on [ensureInitialized]; the real CoreExtension is then never
  /// constructed and the namespace is available for a user extension.
  final bool _installCoreExtension;
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

  /// Test-only override of [PolicyLoop]'s frame-wait function. When
  /// `null`, the loop awaits `SchedulerBinding.instance.endOfFrame`.
  /// Tests that run as plain `test()` (no widget pumping) inject
  /// `() async {}` here so the loop yields without scheduling a frame
  /// the host won't drive.
  Future<void> Function()? _waitForFrameForTesting;

  /// Test-only override of [PolicyLoop]'s wall-clock fn. When `null`,
  /// the loop uses `Stopwatch().elapsedMilliseconds` started at the
  /// loop entry point.
  int Function()? _nowMsForTesting;

  /// Wired in [ensureInitialized]; owns extension lifecycle dispatch and the
  /// per-extension error-handler chain.
  late final ExtensionRegistry _extensionRegistry;

  /// Bounded ring buffer of recent runtime errors (cx6.9).
  late final ErrorRingBuffer _errors;

  /// Session-start anchor used to compute `wallClockOffsetMs` for error
  /// entries. Started in [ensureInitialized].
  late final Stopwatch _sessionClock;

  /// Owns the perception tree for perception-native extensions. Mounted and
  /// unmounted per observation turn; disposed via teardown in [_wireExtensions].
  final PerceptionOwner _perceptionOwner = PerceptionOwner();

  /// Async teardown callbacks registered by user code via
  /// `LeonardAppContext.onTeardown`. Drained LIFO from
  /// [debugReset] (debug/profile only).
  final List<Future<void> Function()> _teardowns = <Future<void> Function()>[];

  /// Captured prior `FlutterError.onError`, restored by [debugReset].
  FlutterExceptionHandler? _priorFlutterOnError;

  /// Captured prior `PlatformDispatcher.onError`, restored by [debugReset].
  ErrorCallback? _priorPlatformOnError;

  /// True once [_installErrorHooks] has run for this binding instance. The
  /// `_instance == null` short-circuit in [ensureInitialized] already
  /// prevents re-hooking; this flag is a defence-in-depth guard.
  bool _errorHooksInstalled = false;

  /// User-supplied list, registration order preserved. cx6.3 reads it.
  List<LeonardExtension> get plugins => List.unmodifiable(_extensions);

  /// The wired extension registry. Extensions are registered in the order they
  /// appear in the `extensions` argument to [ensureInitialized]; downstream
  /// beads (cx6.6 core action tools, cx6.8 stable observation) dispatch
  /// through this registry.
  ExtensionRegistry get extensionRegistry => _extensionRegistry;

  /// No-op (returns null) outside debug/profile.
  /// Throws [StateError] if a different `WidgetsBinding` is active.
  /// Idempotent: second call returns the same instance and does NOT
  /// re-install error hooks or re-register extensions.
  static LeonardBinding? ensureInitialized({
    required List<LeonardExtension> extensions,
    List<String> extraInteractiveTypes = const <String>[],
    int errorBufferCapacity = kDefaultErrorBufferCapacity,
    @visibleForTesting bool installCoreExtension = true,
  }) {
    if (!kDebugMode && !kProfileMode) return null;
    if (_instance != null) return _instance;
    assert(
      errorBufferCapacity > 0,
      'errorBufferCapacity must be > 0 (got $errorBufferCapacity)',
    );
    // BindingBase.debugBindingType() is non-null once any binding has been
    // initialized; it stays null until then. Available in debug and profile
    // (which is the only mode this method runs in), per BindingBase.
    final Type? existingType = BindingBase.debugBindingType();
    if (existingType != null && existingType != LeonardBinding) {
      throw StateError(
        'LeonardBinding cannot be installed: another WidgetsBinding '
        '($existingType) is already active. LeonardBinding '
        'is incompatible with IntegrationTestWidgetsFlutterBinding and '
        'other custom bindings (PRD §6.5).',
      );
    }
    final LeonardBinding binding = LeonardBinding._(
      List.of(extensions),
      List<String>.unmodifiable(extraInteractiveTypes),
      errorBufferCapacity,
      installCoreExtension,
    );
    _instance = binding;
    binding._wireExtensions(binding._extensions);
    return binding;
  }

  /// Shared install path used by both [ensureInitialized] and [run].
  ///
  /// The caller MUST have already set `_instance = this` before
  /// invoking this method, and MUST have already constructed
  /// [LeonardBinding._] (which boots the superclass and installs
  /// the framework's default `FlutterError.onError`). The default is
  /// captured here AFTER boot so the chain forwards into it.
  void _wireExtensions(List<LeonardExtension> plugins) {
    _sessionClock = Stopwatch()..start();
    _errors = ErrorRingBuffer(
      capacity: _errorBufferCapacity,
      sessionClock: _sessionClock,
    );
    _extensionRegistry = ExtensionRegistry(scheduler: this);
    // Host-install CoreExtension FIRST so namespace `core` is reserved
    // before user extensions are registered. The registry's existing
    // duplicate-namespace check then rejects any user extension claiming
    // `core` (PRD §12.1, AC #2 of cx6.6).
    //
    // Test harnesses (e.g. the dogfood loop — lenny-cx6.45) may pass
    // `installCoreExtension: false` to [ensureInitialized] so a caller-
    // supplied stand-in extension can claim the `core` namespace. The
    // production path (`LeonardBinding.run` and the default
    // `ensureInitialized` invocation) always installs the real
    // CoreExtension.
    if (_installCoreExtension) {
      _extensionRegistry.register(CoreExtension(semantics: _semanticsCapture));
    }
    // Register each unique extension namespace into the registry. The
    // legacy `plugins` getter preserves the verbatim list (including
    // duplicates) per cx6.2's contract, but the registry enforces
    // namespace uniqueness — duplicate registrations are logged and
    // skipped so lifecycle dispatch sees each extension exactly once.
    for (final LeonardExtension p in plugins) {
      try {
        _extensionRegistry.register(p);
      } on StateError catch (e) {
        debugPrint('[Leonard] skipping extension ${p.namespace}: $e');
      } on ArgumentError catch (e) {
        debugPrint('[Leonard] skipping extension ${p.namespace}: $e');
      }
    }
    _installErrorHooks();
    _teardowns.add(() async => _perceptionOwner.dispose());
    _registerCoreExtensions();
    _registerDiagnosticsExtension();
    // Run extension initialization in a microtask so it completes before the
    // first frame without blocking the synchronous return.
    scheduleMicrotask(
      () => _extensionRegistry.initializeAll().then(
        (_) => _registerExtensionToolExtensions(),
      ),
    );
  }

  /// High-level entry point. Make this the FIRST Flutter-touching line
  /// of `main()`:
  ///
  /// ```dart
  /// void main() => LeonardBinding.run(MyApp());
  /// ```
  ///
  /// Behaviour by mode:
  ///
  /// - **release** (`kReleaseMode`): no binding is installed, no
  ///   extensions are registered, and [LeonardApp.build] is invoked
  ///   with a release context whose [LeonardAppContext.binding] is
  ///   `null` and whose [LeonardAppContext.onTeardown] is a no-op.
  ///   `runApp(config.app)` is still called.
  /// - **debug/profile**: claims the [WidgetsBinding] slot, calls
  ///   [LeonardApp.build] with a context that exposes the binding,
  ///   wires the returned extensions through the same path as
  ///   [ensureInitialized], then calls `runApp` inside the binding's
  ///   stability zone so user-mode microtasks flip the
  ///   `pendingMicrotasks` edge signal.
  ///
  /// Throws [StateError] if a non-`LeonardBinding` `WidgetsBinding`
  /// is already active when called in debug/profile — Flutter forbids
  /// rebinding once `WidgetsBinding._instance` is set.
  ///
  /// Idempotent: calling `run` a second time in the same process
  /// re-runs [LeonardApp.build] and `runApp` against the existing
  /// binding without reinstalling it or re-registering extensions.
  static void run(LeonardApp app) {
    if (kReleaseMode) {
      final LeonardAppConfig cfg = app.build(const _ReleaseContext());
      runApp(cfg.app);
      return;
    }
    final LeonardBinding? existing = _instance;
    if (existing == null) {
      // Detect a foreign WidgetsBinding *before* entering the stability
      // zone so the error path is plainly synchronous to the caller.
      final Type? existingType = BindingBase.debugBindingType();
      if (existingType != null && existingType != LeonardBinding) {
        throw StateError(
          'LeonardBinding.run cannot install: another WidgetsBinding '
          '($existingType) is already active. Make LeonardBinding.run(...) '
          'the first Flutter-touching line of main() — construct shared '
          'instances (Router, Dio, ProviderContainer) inside '
          'LeonardApp.build, not before.',
        );
      }
      // Install the binding, build the app, and `runApp` inside the SAME
      // zone so Flutter's `BindingBase.debugCheckZone` does not flag a
      // mismatch between "zone where the binding was initialized" and
      // "zone where runApp was called". The zone also intercepts user
      // microtasks for the `pendingMicrotasks` edge signal (cx6.7).
      late final LeonardBinding binding;
      late final LeonardAppConfig cfg;
      runZoned<void>(
        () {
          binding = LeonardBinding._(
            <LeonardExtension>[],
            const <String>[],
            kDefaultErrorBufferCapacity,
            true,
          );
          _instance = binding;
          cfg = app.build(_DebugContext(binding));
          binding._wireExtensions(cfg.extensions);
          runApp(cfg.app);
        },
        zoneSpecification: ZoneSpecification(
          scheduleMicrotask:
              (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
                // _instance is set synchronously in the body above before any
                // microtask ever runs through this hook.
                _instance?.markMicrotaskScheduled();
                parent.scheduleMicrotask(zone, f);
              },
        ),
      );
    } else {
      // Idempotent: prior run/ensureInitialized already installed. Run
      // build + runApp in the stability zone bound to the existing
      // binding so microtasks scheduled from the new app tree still
      // flip the edge signal.
      runZoned<void>(() {
        final LeonardAppConfig cfg = app.build(_DebugContext(existing));
        runApp(cfg.app);
      }, zoneSpecification: stabilityZoneSpec(existing));
    }
  }

  /// Singleton accessor. Returns the active binding; throws [StateError]
  /// if [ensureInitialized] has not been called (or returned null).
  static LeonardBinding get instance {
    final LeonardBinding? b = _instance;
    if (b == null) {
      throw StateError(
        'LeonardBinding has not been initialized. Call '
        'LeonardBinding.ensureInitialized(...) first.',
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
      // Extension handler chain — return value intentionally ignored: the ring
      // buffer always records, and we always forward to the prior handler
      // so framework default behaviour (e.g. dumping to console) survives.
      _extensionRegistry.dispatchError(details);
      _priorFlutterOnError?.call(details);
    };
    _priorPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _errors.add(error.toString(), stack);
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: error,
        stack: stack,
      );
      _extensionRegistry.dispatchError(details);
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
    _registerExtension('$kLeonardExtensionPrefix.core.handshake', (
      String method,
      Map<String, String> parameters,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object?>{
          'protocolVersion': '2',
          'bindingType': 'LeonardBinding',
          'flutterMode': kDebugMode ? 'debug' : 'profile',
          'extensionCount': _extensions.length,
          'extensions': <Map<String, Object?>>[
            for (final ({String namespace, List<String> tools}) m
                in _extensionRegistry.manifest)
              <String, Object?>{'namespace': m.namespace, 'tools': m.tools},
          ],
        }),
      );
    });
    _registerExtension('$kLeonardExtensionPrefix.core.get_semantics', (
      String method,
      Map<String, String> parameters,
    ) async {
      // captureAsync (not the deprecated sync capture) so the agent's
      // primary perception path waits out the first-frame semantics-flush
      // race instead of returning [] on a cold start (lenny-whn).
      final List<Map<String, Object>> recs = await _semanticsCapture
          .captureAsync();
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object>{'semantics': recs, 'count': recs.length}),
      );
    });
    _registerExtension('$kLeonardExtensionPrefix.core.get_recent_errors', (
      String method,
      Map<String, String> parameters,
    ) async {
      final int since = int.tryParse(parameters['since'] ?? '0') ?? 0;
      final List<ErrorEntry> entries = _errors.entriesSince(since);
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object?>{
          'entries': entries
              .map((ErrorEntry e) => e.toJson())
              .toList(growable: false),
          'cursor': entries.isEmpty ? since : _errors.highestSeq,
        }),
      );
    });
    if (kDebugMode) {
      _registerExtension(
        '$kLeonardExtensionPrefix.core.get_stable_observation',
        (String method, Map<String, String> parameters) async {
          try {
            final ObservationRequest req = _decodeObservationRequest(
              parameters,
            );
            final Map<String, Object?> obs = await getStableObservation(req);
            return developer.ServiceExtensionResponse.result(
              jsonEncode(<String, Object?>{
                'type': 'Observation',
                'value': obs,
              }),
            );
          } on FormatException catch (e) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.invalidParams,
              jsonEncode(<String, Object?>{'code': 2, 'message': e.message}),
            );
          }
        },
      );
    }
    if (kDebugMode || kProfileMode) {
      developer.registerExtension('$kLeonardExtensionPrefix.core.screenshot', (
        String method,
        Map<String, String> params,
      ) async {
        try {
          final ScreenshotResult result = await captureScreenshot(this);
          return developer.ServiceExtensionResponse.result(
            jsonEncode(<String, dynamic>{'result': result.toJson()}),
          );
        } on ScreenshotUnavailable catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            jsonEncode(<String, dynamic>{'code': 1, 'message': e.reason}),
          );
        }
      });
    }
  }

  void _registerDiagnosticsExtension() {
    if (!kDebugMode && !kProfileMode) return;
    _registerExtension('$kLeonardExtensionPrefix.core.diagnostics_warnings', (
      String method,
      Map<String, String> parameters,
    ) async {
      try {
        _cachedDiagnostics ??= _runDiagnostic();
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'ok': true,
            'results': _cachedDiagnostics!
                .map((InteractiveSemanticsWarning w) => w.toJson())
                .toList(),
          }),
        );
      } catch (e, st) {
        debugPrint('exploration: diagnostics walk failed: $e\n$st');
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{
            'ok': false,
            'error': e.toString(),
            'results': const <Object?>[],
          }),
        );
      }
    });
  }

  /// Registers every extension tool as a real VM service extension so
  /// live VM-service callers can invoke extension tools by name.
  ///
  /// Iterates [ExtensionRegistry.mergedTools] (keyed by `<ns>.<tool>`)
  /// and calls [_registerExtension] for each entry, exposing it at
  /// `ext.exploration.<ns>.<tool>`. This also populates
  /// [_extensionCallbacks] so [invokeServiceExtension] can reach extension
  /// tools in tests without a live VM connection.
  ///
  /// Called once, in the microtask that runs [ExtensionRegistry.initializeAll],
  /// after all extensions have finished their own [initialize] callbacks.
  /// Must be the sole registration site for extension tools; extension
  /// [initialize] implementations must NOT call
  /// [ExtensionContext.registerExtension] for their own tools (doing so
  /// double-registers and [developer.registerExtension] throws).
  ///
  /// Gated on [kDebugMode] / [kProfileMode] (same gate as every other
  /// extension in this class).
  void _registerExtensionToolExtensions() {
    if (!kDebugMode && !kProfileMode) return;
    final Map<String, LeonardTool> tools = _extensionRegistry.mergedTools();
    for (final MapEntry<String, LeonardTool> entry in tools.entries) {
      final String method = '$kLeonardExtensionPrefix.${entry.key}';
      final LeonardTool tool = entry.value;
      _registerExtension(method, (String m, Map<String, String> params) async {
        final Map<String, Object?> args = decodeServiceExtensionParams(params);
        final String body = await dispatchToolToEnvelope(tool, args);
        return developer.ServiceExtensionResponse.result(body);
      });
    }
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

  /// Decode the VM-extension parameter map into an [ObservationRequest].
  ///
  /// `developer.registerExtension` hands us a flat
  /// `Map<String, String>`; nested JSON arrives as a JSON-encoded
  /// string under known keys. We only round-trip `extensionBudgets` here
  /// because every other field is a scalar.
  ObservationRequest _decodeObservationRequest(Map<String, String> params) {
    final Map<String, dynamic> j = <String, dynamic>{};
    for (final MapEntry<String, String> e in params.entries) {
      switch (e.key) {
        case 'extensionBudgets':
          // extensionBudgets: '{"a":256,"b":512}' (JSON-encoded).
          j[e.key] = jsonDecode(e.value);
          break;
        case 'includeScreenshot':
          j[e.key] = e.value == 'true';
          break;
        case 'actionRelativeBudgetMs':
        case 'quietFrameN':
        case 'boundedStabilityBudgetMs':
        case 'errorCursor':
          j[e.key] = int.tryParse(e.value) ?? e.value;
          break;
        default:
          j[e.key] = e.value;
      }
    }
    return ObservationRequest.fromJson(j);
  }

  /// Hash of the live route stack (best-effort Navigator 1.0 names).
  /// Used by [PolicyLoop] to detect route changes during the
  /// `action-relative` policy. Stable across invocations for the same
  /// list contents.
  int _routeStackHash() => Object.hashAll(bestEffortRouteStack());

  /// Hash of the current semantics tree. Cheap proxy for "did the tree
  /// change?": we hash the count plus each record's `id`/`role`/`rect`.
  /// Walk skipped under release.
  int _semanticsTreeHash() {
    final List<Map<String, Object>> recs = _semanticsCapture.capture();
    final List<int> tokens = <int>[recs.length];
    for (final Map<String, Object> r in recs) {
      tokens.add(r['id'].hashCode);
      tokens.add(r['role'].hashCode);
      tokens.add(Object.hashAll((r['rect'] as List<Object?>)));
    }
    return Object.hashAll(tokens);
  }

  /// Compose the stable-observation bundle for the current turn.
  ///
  /// Polls cx6.4's framework signals + every extension's `busyState()`
  /// until [req]'s policy terminates, then captures the merged JSON
  /// observation: core fragment + per-extension fragments under
  /// `extensions.<namespace>`.
  ///
  /// kDebugMode-gated: callers in release/profile receive a stub empty
  /// observation. The VM extension is not registered in those modes,
  /// so this surface is reachable only via tests.
  Future<Map<String, Object?>> getStableObservation(
    ObservationRequest req,
  ) async {
    final PolicyLoop loop = PolicyLoop(
      snapshot: frameworkBusySnapshot,
      pollBusyStates: () async => _extensionRegistry.busyStateAll(),
      semanticsHash: _semanticsTreeHash,
      routeHash: _routeStackHash,
      waitForFrame: _waitForFrameForTesting,
      nowMs: _nowMsForTesting,
    );
    final PolicyTick tick = await loop.run(req);
    final StabilityMetadata stability = StabilityMetadata(
      policy: req.policy,
      terminatedBy: tick.reason,
      durationMs: tick.durationMs,
      frameworkBusy: frameworkBusySnapshot().toJson(),
      extensionsBusy: tick.extensionsBusy,
    );

    Future<String?> screenshotCaptureOrNull() async {
      try {
        final ScreenshotResult sr = await captureScreenshot(this);
        return sr.pngBase64;
      } on ScreenshotUnavailable {
        return null;
      }
    }

    // Core fragment via the SINGLE perception path: compute the core
    // primitives, build the core Seed from them, mount/serialize.
    // serializePerceptionFragment strips the top Node('core') name and
    // emits {semantics, routes, errors, stability [, screenshot_png_b64]}
    // in that key order.
    final CoreFragmentValues coreValues = await computeCoreFragmentValues(
      captureSemantics: _semanticsCapture.captureAsync,
      errorsSince: (int? cursor) => _errors.entriesSince(cursor ?? 0),
      stability: stability,
      includeScreenshot: req.includeScreenshot,
      captureScreenshot: req.includeScreenshot ? screenshotCaptureOrNull : null,
      errorCursor: req.errorCursor,
    );
    _perceptionOwner.unmountRoot();
    final Branch coreRoot = _perceptionOwner.mountRoot(
      buildCorePerceptionSeed(
        semantics: coreValues.semantics,
        routes: coreValues.routes,
        errors: coreValues.errors,
        stability: coreValues.stability,
        screenshot: coreValues.screenshot,
      ),
    );
    final Map<String, Object?> core = serializePerceptionFragment(coreRoot);

    // Enforce the 4KB core budget: on overrun, replace with the
    // truncation marker (still as a JSON object) and warn.
    final BudgetedJson coreEnc = encodeWithBudget(core, kCoreBudgetBytes);
    Map<String, Object?> coreOut;
    if (coreEnc.truncated) {
      developer.log(
        'core fragment truncated (${coreEnc.bytes} bytes after marker)',
        name: 'exploration',
      );
      coreOut = jsonDecode(coreEnc.json) as Map<String, Object?>;
    } else {
      coreOut = core;
    }

    final List<String> namespaces = _extensionRegistry.namespaces;
    final Map<String, int> budgets = distributeExtensionBudgets(
      req.extensionBudgets,
      namespaces,
    );

    final Map<String, Object?> extensionsOut = <String, Object?>{};

    // SINGLE observation loop, registration order. Tools-only extensions
    // (no PerceptionExtension mixin) contribute no fragment — exactly
    // mirroring the retired observe() => null. For each PerceptionExtension:
    // prepareForObservation() (side-effect seam) runs FIRST, then the
    // idle gate (reproduces observe()==null suppression), then
    // mount → build → serialize → budget under build isolation.
    for (final LeonardExtension plugin in _extensionRegistry.plugins) {
      if (plugin is! PerceptionExtension) continue;
      final PerceptionExtension pp = plugin;
      final String ns = plugin.namespace;
      try {
        pp.prepareForObservation();
        if (pp.isPerceptionIdle()) continue;
        _perceptionOwner.unmountRoot();
        final Branch root = _perceptionOwner.mountRoot(pp.buildPerception());
        final Map<String, Object?> frag = serializePerceptionFragment(root);
        final BudgetedJson enc = encodeWithBudget(frag, budgets[ns] ?? 0);
        if (enc.truncated) {
          developer.log(
            'plugin $ns fragment truncated '
            '(was ${jsonDecode(enc.json)['originalBytes']} bytes, '
            'budget ${budgets[ns]})',
            name: 'exploration',
          );
          extensionsOut[ns] = jsonDecode(enc.json);
        } else {
          extensionsOut[ns] = frag;
        }
      } catch (err, st) {
        developer.log(
          'plugin $ns threw during observation: $err\n$st',
          name: 'exploration',
        );
      }
    }

    return <String, Object?>{...coreOut, 'extensions': extensionsOut};
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
    String name,
    Map<String, String> args,
  ) async {
    final _ExtCallback? cb = _extensionCallbacks[name];
    if (cb == null) {
      throw StateError('No extension registered with name "$name".');
    }
    final developer.ServiceExtensionResponse resp = await cb(name, args);
    return resp.result ?? '';
  }

  /// Test-only: dispatch a extension tool by its fully-qualified service
  /// extension method name (e.g. `ext.exploration.sample.echo`).
  ///
  /// Extension tools are registered by [_registerExtensionToolExtensions] via [_registerExtension],
  /// which populates both [developer.registerExtension] and [_extensionCallbacks]. They can
  /// therefore also be reached through [invokeServiceExtension]. This helper resolves the
  /// tool via [extensionRegistry]'s `mergedTools()` map (keyed by the qualified `<ns>.<tool>`
  /// form) and wraps the result in the canonical `{ok, value, error[, trace]}` envelope via
  /// [dispatchToolToEnvelope].
  ///
  /// Throws [ArgumentError] when the method name does not start with
  /// `ext.exploration.`, is missing the `<ns>.<tool>` tail, or
  /// when no tool is registered for the qualified name.
  @visibleForTesting
  Future<String> invokeExtensionTool(
    String method,
    Map<String, String> params,
  ) async {
    const String prefix = '$kLeonardExtensionPrefix.';
    if (!method.startsWith(prefix)) {
      throw ArgumentError.value(method, 'method', 'must start with "$prefix"');
    }
    final String tail = method.substring(prefix.length);
    final int dot = tail.indexOf('.');
    if (dot <= 0 || dot == tail.length - 1) {
      throw ArgumentError.value(method, 'method', 'malformed <ns>.<tool>');
    }
    final Map<String, LeonardTool> merged = _extensionRegistry.mergedTools();
    final LeonardTool? tool = merged[tail];
    if (tool == null) {
      throw ArgumentError.value(
        method,
        'method',
        'no tool registered for $tail',
      );
    }
    final Map<String, Object?> args = decodeServiceExtensionParams(params);
    return dispatchToolToEnvelope(tool, args);
  }

  /// Test-only: install a custom root provider for the diagnostics walker.
  /// Pass null to restore the live `rootElement` lookup.
  @visibleForTesting
  void debugSetDiagnosticsRootProviderForTesting(
    DiagnosticsRootProvider? provider,
  ) {
    _diagnosticsRootProviderForTesting = provider;
    _cachedDiagnostics = null;
  }

  /// Test-only: install overrides for the [PolicyLoop]'s frame-wait and
  /// wall-clock so tests running outside a pumped widget tester never
  /// block on `SchedulerBinding.endOfFrame`.
  @visibleForTesting
  void debugSetPolicyLoopSeamsForTesting({
    Future<void> Function()? waitForFrame,
    int Function()? nowMs,
  }) {
    _waitForFrameForTesting = waitForFrame;
    _nowMsForTesting = nowMs;
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
  /// `ensureInitialized` call starts from a clean slate. Also drains
  /// any registered `onTeardown` callbacks LIFO; reset waits for each
  /// callback to complete before continuing.
  @visibleForTesting
  static Future<void> debugReset() async {
    final LeonardBinding? b = _instance;
    if (b != null) {
      while (b._teardowns.isNotEmpty) {
        await b._teardowns.removeLast()();
      }
      b._uninstallErrorHooks();
    }
    _instance = null;
  }

  /// Test-only alias: clears the singleton so tests that call
  /// `ensureInitialized` can isolate setup. Intentionally identical to
  /// [debugReset] — keeps the published name consistent with the bead
  /// spec.
  @visibleForTesting
  static Future<void> resetForTesting() => debugReset();

  /// Test-only: replace the registered teardown callbacks. Useful for
  /// isolating LIFO-order assertions from any callbacks left over from
  /// earlier tests sharing the singleton.
  @visibleForTesting
  void debugSetTeardownsForTesting(List<Future<void> Function()> v) {
    _teardowns
      ..clear()
      ..addAll(v);
  }

  /// Test-only: drain registered teardown callbacks LIFO without
  /// touching the rest of the binding state (no error-hook restore, no
  /// singleton clear). Intended for tests that exercise teardown
  /// ordering against the long-lived singleton install.
  @visibleForTesting
  Future<void> debugDrainTeardownsForTesting() async {
    while (_teardowns.isNotEmpty) {
      await _teardowns.removeLast()();
    }
  }

  /// Returns a `ZoneSpecification` that intercepts microtask scheduling so
  /// the binding's `pendingMicrotasks` edge signal flips immediately when
  /// the user-mode app schedules a microtask. Wrap the user `runApp` (or
  /// app entrypoint) with `runZoned(..., zoneSpecification: spec)` to
  /// install — currently consumed by integration tests; cx6.7's
  /// `installAndRun` will install it for production.
  static ZoneSpecification stabilityZoneSpec(LeonardBinding binding) {
    return ZoneSpecification(
      scheduleMicrotask:
          (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
            binding.markMicrotaskScheduled();
            parent.scheduleMicrotask(zone, f);
          },
    );
  }
}

/// Debug/profile context handed to [LeonardApp.build] when
/// [LeonardBinding.run] has installed the binding.
class _DebugContext implements LeonardAppContext {
  const _DebugContext(this._binding);

  final LeonardBinding _binding;

  @override
  LeonardBinding? get binding => _binding;

  @override
  bool get isProductionMode => false;

  @override
  void onTeardown(Future<void> Function() cb) {
    _binding._teardowns.add(cb);
  }
}

/// Release context handed to [LeonardApp.build] when
/// [LeonardBinding.run] runs in `kReleaseMode`. No binding is
/// installed; [onTeardown] is a no-op.
class _ReleaseContext implements LeonardAppContext {
  const _ReleaseContext();

  @override
  LeonardBinding? get binding => null;

  @override
  bool get isProductionMode => true;

  @override
  void onTeardown(Future<void> Function() cb) {
    // Intentional no-op in release.
  }
}
