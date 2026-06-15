import 'dart:convert';

/// Result of [encodeWithBudget]: the JSON string to embed in the
/// response, the byte length of that string, and a `truncated` flag
/// indicating whether the original fragment fit within `budget` bytes.
class BudgetedJson {
  const BudgetedJson({
    required this.json,
    required this.bytes,
    required this.truncated,
  });

  /// JSON-encoded payload to embed in the response. When [truncated] is
  /// `true`, this is a marker object rather than the original fragment.
  final String json;

  /// UTF-8 byte length of [json].
  final int bytes;

  /// `true` when the original fragment exceeded `budget` and has been
  /// replaced with a truncation marker.
  final bool truncated;
}

/// JSON-encode [fragment]; if the encoded form exceeds [budget] bytes
/// (UTF-8), return a truncation-marker object instead.
///
/// Marker shape (PRD §11.4): `{"_truncated": true, "originalBytes": N,
/// "budgetBytes": M}`. The marker itself is well below any sane budget
/// so callers do not have to handle a marker that itself overruns.
BudgetedJson encodeWithBudget(Map<String, Object?> fragment, int budget) {
  final String raw = jsonEncode(fragment);
  final int rawBytes = utf8.encode(raw).length;
  if (rawBytes <= budget) {
    return BudgetedJson(json: raw, bytes: rawBytes, truncated: false);
  }
  final String marker = jsonEncode(<String, Object?>{
    '_truncated': true,
    'originalBytes': rawBytes,
    'budgetBytes': budget,
  });
  return BudgetedJson(
    json: marker,
    bytes: utf8.encode(marker).length,
    truncated: true,
  );
}

/// Default core fragment serialized budget, in bytes (PRD §11.4).
const int kCoreBudgetBytes = 4096;

/// Default per-plugin observation budget, in bytes.
const int kDefaultExtensionBudgetBytes = 1024;

/// Total cap on the sum of per-plugin observation budgets, in bytes.
const int kExtensionBudgetTotalCapBytes = 2048;

/// Compute the effective per-plugin budget map.
///
/// For each namespace in [namespaces] (registration order), the
/// effective budget is `requested[ns]` if present, otherwise [defaultPer].
/// If the sum of effective budgets exceeds [totalCap], every entry is
/// scaled down by `totalCap / sum` (floor) so the sum no longer exceeds
/// the cap.
Map<String, int> distributeExtensionBudgets(
  Map<String, int> requested,
  List<String> namespaces, {
  int defaultPer = kDefaultExtensionBudgetBytes,
  int totalCap = kExtensionBudgetTotalCapBytes,
}) {
  final Map<String, int> effective = <String, int>{
    for (final String ns in namespaces) ns: requested[ns] ?? defaultPer,
  };
  final int sum = effective.values.fold<int>(0, (int a, int b) => a + b);
  if (sum <= totalCap) {
    return Map<String, int>.unmodifiable(effective);
  }
  final double scale = totalCap / sum;
  return Map<String, int>.unmodifiable(<String, int>{
    for (final MapEntry<String, int> e in effective.entries)
      e.key: (e.value * scale).floor(),
  });
}
