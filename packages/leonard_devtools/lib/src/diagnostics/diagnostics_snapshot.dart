import 'package:genesis_foundation/genesis_foundation.dart';

/// Loads one diagnostics snapshot from the current target.
typedef DiagnosticsSnapshotLoader = Future<TreeSnapshot> Function();

/// Decodes a `get_diagnostics_tree` response — wrapped in the VM `value`
/// envelope or bare — into a contract-1 [TreeSnapshot].
///
/// Every malformed input (missing/non-map `diagnostics_tree`, unsupported
/// contract version, or a payload the foundation decoder rejects) is
/// normalized to [FormatException].
TreeSnapshot decodeDiagnosticsSnapshot(Map<String, Object?> response) {
  final Object? wrapped = response['value'];
  final Map<String, Object?> payload = wrapped is Map
      ? Map<String, Object?>.from(wrapped)
      : response;
  final Object? raw = payload['diagnostics_tree'];
  if (raw is! Map) {
    throw const FormatException(
      'get_diagnostics_tree response missing diagnostics_tree map',
    );
  }
  try {
    final TreeSnapshot snapshot = TreeSnapshot.fromJson(
      Map<String, Object?>.from(raw),
    );
    if (snapshot.contractVersion != 1) {
      throw FormatException(
        'unsupported diagnostics contract ${snapshot.contractVersion}',
      );
    }
    return snapshot;
  } on CheckedFromJsonException catch (error) {
    throw FormatException('malformed diagnostics_tree: $error');
  } on FormatException catch (error) {
    throw FormatException('malformed diagnostics_tree: $error');
  }
}
