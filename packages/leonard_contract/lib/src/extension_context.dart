import 'dart:async';
import 'dart:developer' as developer;

import 'package:meta/meta.dart';

/// VM service extension handler signature.
typedef ExtensionHandler =
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> parameters,
    );

/// Per-extension context handed to `LeonardExtension.initialize`.
///
/// Auto-namespaces VM service extensions under
/// `ext.exploration.<namespace>.<suffix>`.
class ExtensionContext {
  ExtensionContext({required this.namespace});

  /// The owning extension's namespace (validated by the registry).
  final String namespace;

  /// Compose the fully-qualified VM service extension method name for a
  /// given namespace and suffix.
  @visibleForTesting
  static String buildExtensionMethodName(String ns, String suffix) =>
      'ext.exploration.$ns.$suffix';

  /// Register a VM service extension under this extension's namespace.
  ///
  /// The extension is exposed at
  /// `ext.exploration.<namespace>.<suffix>`.
  void registerExtension(String suffix, ExtensionHandler handler) {
    developer.registerExtension(
      buildExtensionMethodName(namespace, suffix),
      handler,
    );
  }
}
