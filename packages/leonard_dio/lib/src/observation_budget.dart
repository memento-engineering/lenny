import 'dart:convert';

/// Per-plugin observation budget in bytes (PRD §7.4).
const int kExtensionBudgetBytes = 1024;

/// Trim [frag] until its UTF-8 JSON encoding fits inside [budget] bytes.
///
/// Drops the most recent `recent_completed` entries first, then in-flight
/// entries; tags the result with `'truncated': true` once any drop occurs.
Map<String, Object?> truncateToBudget(Map<String, Object?> frag, int budget) {
  if (utf8.encode(jsonEncode(frag)).length <= budget) return frag;

  final inFlight = (frag['in_flight'] as List).toList();
  final recent = (frag['recent_completed'] as List).toList();

  while (inFlight.isNotEmpty || recent.isNotEmpty) {
    if (recent.isNotEmpty) {
      recent.removeLast();
    } else {
      inFlight.removeLast();
    }
    final next = <String, Object?>{
      'in_flight': inFlight,
      'recent_completed': recent,
      'truncated': true,
    };
    if (utf8.encode(jsonEncode(next)).length <= budget) return next;
  }
  return <String, Object?>{
    'in_flight': const <Object?>[],
    'recent_completed': const <Object?>[],
    'truncated': true,
  };
}
