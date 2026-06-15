import 'package:flutter/widgets.dart';

import '../contract/extension.dart';
import 'leonard_binding.dart';

/// High-level entry point for Flutter apps that want
/// `LeonardBinding` installed before any user code constructs
/// Flutter-aware objects (e.g. `GoRouter`, `MaterialApp`).
///
/// Implement this and pass it to [LeonardBinding.run]:
///
/// ```dart
/// void main() => LeonardBinding.run(MyApp());
///
/// class MyApp implements LeonardApp {
///   @override
///   LeonardAppConfig build(LeonardAppContext ctx) {
///     // Construct Router, ProviderContainer, Dio, etc. *here* — by the
///     // time this callback runs, LeonardBinding has already claimed
///     // the WidgetsBinding slot, so subsequent
///     // WidgetsFlutterBinding.ensureInitialized() calls are idempotent.
///     return LeonardAppConfig(
///       extensions: <LeonardExtension>[/* ... */],
///       app: const MyMaterialApp(),
///     );
///   }
/// }
/// ```
abstract class LeonardApp {
  /// Construct the app's extensions + root widget. Called by
  /// [LeonardBinding.run] after the binding slot has been claimed
  /// (debug/profile) or at start-up (release).
  LeonardAppConfig build(LeonardAppContext ctx);
}

/// Carrier returned from [LeonardApp.build]: the extensions to register
/// with the binding (debug/profile only; ignored in release) and the
/// root widget to hand to `runApp`.
class LeonardAppConfig {
  const LeonardAppConfig({
    required this.extensions,
    required this.app,
  });

  /// Extensions registered through the same code path as
  /// [LeonardBinding.ensureInitialized]'s `extensions:` argument.
  /// `CoreExtension` is registered first by the host; these follow in
  /// order. Empty list is permitted.
  final List<LeonardExtension> extensions;

  /// Root widget passed to `runApp`. In debug/profile, the call to
  /// `runApp` happens inside the binding's stability zone so user-mode
  /// microtasks flip the binding's `pendingMicrotasks` edge signal.
  final Widget app;
}

/// Context handed to [LeonardApp.build]. In release, [binding] is
/// null and [onTeardown] is a no-op; user code can branch on
/// [isProductionMode] to skip dev-only wiring.
abstract class LeonardAppContext {
  /// The active binding, or `null` in release where no binding is
  /// installed.
  LeonardBinding? get binding;

  /// `true` iff `kReleaseMode` (i.e. neither `kDebugMode` nor
  /// `kProfileMode`).
  bool get isProductionMode;

  /// Register an async callback to run when the binding is reset
  /// (debug/profile only; release is a no-op). Callbacks fire in LIFO
  /// order from `LeonardBinding.debugReset()` and complete before
  /// reset returns.
  void onTeardown(Future<void> Function() cb);
}
