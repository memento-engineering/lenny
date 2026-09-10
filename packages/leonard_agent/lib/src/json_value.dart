import 'dart:collection';

/// Compares JSON-compatible values recursively.
///
/// Map ordering is ignored while list ordering is significant.
bool jsonValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!jsonValuesEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!jsonValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Returns a value hash consistent with [jsonValuesEqual].
int jsonValueHash(Object? value) {
  if (value is Map) {
    final SplayTreeMap<dynamic, dynamic> sorted =
        SplayTreeMap<dynamic, dynamic>(
          (dynamic a, dynamic b) => a.toString().compareTo(b.toString()),
        )..addAll(value);
    return Object.hashAll(<int>[
      for (final MapEntry<dynamic, dynamic> entry in sorted.entries)
        Object.hash(entry.key, jsonValueHash(entry.value)),
    ]);
  }
  if (value is List) return Object.hashAll(value.map(jsonValueHash));
  return value.hashCode;
}
