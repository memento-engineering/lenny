/// Request-URL construction and transport hygiene shared by the
/// Appium-backed native backends.
library;

import 'package:http/http.dart' as http;

import 'native_backend.dart';

/// Joins the root-relative Appium endpoint [path] onto [server], keeping any
/// base path the server is mounted under (Appium 1.x `/wd/hub`, a Selenium
/// Grid, a reverse proxy).
///
/// `Uri.resolve` cannot do this: a root-relative reference replaces the base
/// path, so `http://h:4723/wd/hub` resolving `/session` loses `/wd/hub`. For a
/// server with an empty or `/` path the result equals `server.resolve(path)`.
Uri appiumEndpoint(Uri server, String path) {
  final String base = server.path.endsWith('/')
      ? server.path.substring(0, server.path.length - 1)
      : server.path;
  return server.replace(path: '$base$path');
}

/// Sends one Appium request through [send], turning a transport failure (no
/// HTTP response at all) into a [NativeException] coded
/// [NativeException.transportErrorCode].
///
/// `package:http`'s `ClientException` carries the full request URI, and a
/// cloud grid's server URL carries its access key as userinfo
/// (`https://user:key@hub…/wd/hub`). Letting it propagate writes the key into
/// any log that prints the failure, so the message is redacted here, at the
/// source, with [redactCredentials].
Future<http.Response> appiumSend(Future<http.Response> Function() send) async {
  try {
    return await send();
  } on http.ClientException catch (e) {
    final String where = e.uri == null ? '' : ' (${e.uri})';
    throw NativeException(
      redactCredentials('transport error: ${e.message}$where'),
      code: NativeException.transportErrorCode,
    );
  }
}

/// Masks the userinfo of every URL in [text]:
/// `https://user:key@host/wd/hub` becomes `https://***@host/wd/hub`.
String redactCredentials(String text) => text.replaceAllMapped(
  RegExp(r'([A-Za-z][A-Za-z0-9+.\-]*://)[^/\s@]+@'),
  (Match m) => '${m[1]}***@',
);
