import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Error handler signature; return `true` to claim the error and stop
/// further chaining, `false` to let the next handler attempt it.
typedef ErrorHandler = bool Function(FlutterErrorDetails details);

/// VM service extension handler signature.
typedef ExtensionHandler = Future<developer.ServiceExtensionResponse>
    Function(String method, Map<String, String> parameters);

/// Per-plugin context handed to [ExplorationPlugin.initialize].
///
/// Auto-namespaces VM service extensions under
/// `ext.exploration.<namespace>.<suffix>` and gates frame
/// callbacks through the host scheduler.
class PluginContext {
  PluginContext({required this.namespace, required SchedulerBinding scheduler})
      : _scheduler = scheduler;

  /// The owning plugin's namespace (validated by the registry).
  final String namespace;

  final SchedulerBinding _scheduler;

  /// Registered error handlers, in registration order. Read by the
  /// registry's error-dispatch loop.
  final List<ErrorHandler> errorHandlers = <ErrorHandler>[];

  /// Compose the fully-qualified VM service extension method name for a
  /// given namespace and suffix.
  @visibleForTesting
  static String buildExtensionMethodName(String ns, String suffix) =>
      'ext.exploration.$ns.$suffix';

  /// Append [handler] to this plugin's error handler chain.
  void registerErrorHandler(ErrorHandler handler) {
    errorHandlers.add(handler);
  }

  /// Register a VM service extension under this plugin's namespace.
  ///
  /// The extension is exposed at
  /// `ext.exploration.<namespace>.<suffix>`.
  void registerExtension(String suffix, ExtensionHandler handler) {
    developer.registerExtension(
      buildExtensionMethodName(namespace, suffix),
      handler,
    );
  }

  /// Forward [callback] to [SchedulerBinding.addPostFrameCallback].
  void registerFrameCallback(FrameCallback callback) {
    _scheduler.addPostFrameCallback(callback);
  }
}
