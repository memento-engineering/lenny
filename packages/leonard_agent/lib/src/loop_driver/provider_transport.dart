/// Classification of PROVIDER TRANSPORT failures (PRD §17).
///
/// A transport failure is an HTTP/socket-level fault raised while awaiting or
/// streaming the model response — the wire died, not the model. It is a
/// RETRYABLE turn failure (`reason: 'provider_transport'`), never a
/// session-ending harness error: one closed stream must not end a session that
/// still has turns left.
///
/// `leonard_agent/lib` is `dart:io`-free (`tool/check_no_dart_io.sh`), so the
/// `dart:io` transport exceptions are matched by runtime-type NAME; the
/// web-safe ones ([ClientException], [TimeoutException]) are matched by type.
library;

import 'dart:async';

import 'package:http/http.dart' show ClientException;

/// Runtime-type names of the `dart:io` transport exceptions treated as
/// provider transport failures.
const Set<String> kIoTransportExceptionNames = <String>{
  'SocketException',
  'HttpException',
  'HandshakeException',
  'TlsException',
  'WebSocketException',
};

/// Maximum length of a footer detail message, so one long exception cannot
/// bloat the trajectory footer.
const int kMaxDetailLength = 200;

/// True when [error] is a provider TRANSPORT failure — the request or its
/// response stream died before the model produced output.
bool isProviderTransportError(Object error) =>
    error is ClientException ||
    error is TimeoutException ||
    kIoTransportExceptionNames.contains(error.runtimeType.toString());

/// Raised by `decideAndValidate` when `ModelProvider.decide` failed with a
/// transport fault rather than a model-output fault. `LoopDriver.runTurn`
/// converts it into a `provider_transport` [TurnFailure].
class ProviderTransportFailure implements Exception {
  /// Wraps the underlying transport [cause].
  const ProviderTransportFailure(this.cause);

  /// The original transport exception (e.g. a [ClientException]).
  final Object cause;

  /// The cause's runtime-type name, e.g. `ClientException`. Written into the
  /// trajectory footer's `termination_detail`.
  String get errorClass => cause.runtimeType.toString();

  @override
  String toString() => 'ProviderTransportFailure: $errorClass: $cause';
}

final RegExp _kAuthorizationHeader = RegExp(
  r'(authorization\s*:\s*)[^\n]+',
  caseSensitive: false,
);
final RegExp _kBearerToken = RegExp(
  r'(bearer\s+)[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
final RegExp _kQueryCredential = RegExp(
  r'([?&](?:token|api_key|apikey|access_token)=)[^&\s]+',
  caseSensitive: false,
);
final RegExp _kApiKeyLiteral = RegExp(r'\b(sk-)[A-Za-z0-9._-]{8,}');

/// Replaces credential-shaped substrings of [text] with `<redacted>`.
///
/// An endpoint URL is configuration, not a credential, and survives
/// byte-identical — the same call the panel receipt's `kSecretNames` makes in
/// `tool/verify_panel_selfdrive_receipt.dart`.
String scrubCredentials(String text) => text
    .replaceAllMapped(_kAuthorizationHeader, (Match m) => '${m[1]}<redacted>')
    .replaceAllMapped(_kBearerToken, (Match m) => '${m[1]}<redacted>')
    .replaceAllMapped(_kQueryCredential, (Match m) => '${m[1]}<redacted>')
    .replaceAllMapped(_kApiKeyLiteral, (Match m) => '${m[1]}<redacted>');

/// Footer-safe rendering of [error]: its runtime type, then its
/// credential-scrubbed message clipped to [kMaxDetailLength].
///
/// Never returns an empty string — a footer that says `harness_error` must
/// always say WHY, including when nothing was recorded.
String describeThrowable(Object? error) {
  if (error == null) return 'unclassified: no exception recorded';
  final String message = scrubCredentials(error.toString());
  final String clipped = message.length > kMaxDetailLength
      ? '${message.substring(0, kMaxDetailLength)}…'
      : message;
  return '${error.runtimeType}: $clipped';
}
