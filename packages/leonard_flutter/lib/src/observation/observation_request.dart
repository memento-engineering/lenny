import 'dart:developer' as developer;

/// Stability policy selector for [getStableObservation] (PRD §9.1).
///
/// - [actionRelative] (default): terminate on the first of route change,
///   semantics change, all-idle (framework + plugins), or
///   `actionRelativeBudgetMs` elapsed.
/// - [quietFrame]: terminate after `quietFrameN` consecutive idle
///   frames. No wall-clock cap on this policy itself.
/// - [boundedStability]: terminate on quiet-frame condition OR
///   `boundedStabilityBudgetMs` elapsed. On budget the response is still
///   captured and tagged.
enum StabilityPolicy { actionRelative, quietFrame, boundedStability }

/// Wire mapping for [StabilityPolicy].
///
/// Wire tokens are kebab-case to match the JSON contract documented in
/// PRD §9.1; in-Dart enum names are camelCase.
const Map<StabilityPolicy, String> kStabilityPolicyWireNames =
    <StabilityPolicy, String>{
  StabilityPolicy.actionRelative: 'action-relative',
  StabilityPolicy.quietFrame: 'quiet-frame',
  StabilityPolicy.boundedStability: 'bounded-stability',
};

/// Hard upper bound for any `*BudgetMs` request override (PRD §9.1).
///
/// Requests above this value are clamped down and a single
/// `developer.log` warning is emitted per offending field.
const int kMaxBudgetMs = 30000;

/// Default `actionRelativeBudgetMs` per PRD §9.1.
const int kDefaultActionRelativeBudgetMs = 800;

/// Default `quietFrameN` per PRD §9.1.
const int kDefaultQuietFrameN = 2;

/// Default `boundedStabilityBudgetMs` per PRD §9.1.
const int kDefaultBoundedStabilityBudgetMs = 1500;

/// Decoded request payload for `ext.exploration.core.get_stable_observation`.
class ObservationRequest {
  const ObservationRequest({
    this.policy = StabilityPolicy.actionRelative,
    this.actionRelativeBudgetMs = kDefaultActionRelativeBudgetMs,
    this.quietFrameN = kDefaultQuietFrameN,
    this.boundedStabilityBudgetMs = kDefaultBoundedStabilityBudgetMs,
    this.includeScreenshot = false,
    this.extensionBudgets = const <String, int>{},
    this.errorCursor,
  });

  /// Selected policy. Defaults to [StabilityPolicy.actionRelative].
  final StabilityPolicy policy;

  /// Wall-clock cap for `action-relative` policy, in ms.
  final int actionRelativeBudgetMs;

  /// Required idle-frame streak length for `quiet-frame` policy.
  final int quietFrameN;

  /// Wall-clock cap for `bounded-stability` policy, in ms.
  final int boundedStabilityBudgetMs;

  /// When `true`, the response includes `screenshot_png_b64` from cx6.7.
  final bool includeScreenshot;

  /// Per-namespace plugin observation budget overrides, in bytes. Plugins
  /// not present in the map fall back to the 1024-byte default. The sum
  /// of effective budgets is capped at 2048 bytes; overshoots are scaled
  /// proportionally (see `distributeExtensionBudgets`).
  final Map<String, int> extensionBudgets;

  /// Cursor for the cx6.9 error ring. When `null`, `0` is used (i.e. the
  /// full retained history is returned).
  final int? errorCursor;

  /// Decode the JSON shape supplied via the VM service extension.
  ///
  /// `policy` is parsed by wire token (`action-relative`, `quiet-frame`,
  /// `bounded-stability`). Unknown tokens throw [FormatException].
  ///
  /// Any `*BudgetMs` strictly greater than [kMaxBudgetMs] is clamped to
  /// [kMaxBudgetMs] and a `developer.log` warning is emitted naming the
  /// field. Negative budgets are clamped to `0` without warning (defence
  /// in depth — the policy loop also bounds these).
  factory ObservationRequest.fromJson(Map<String, dynamic> j) {
    final StabilityPolicy policy = _policyFromWire(j['policy']);

    final int ar = _clampBudget(
      j['actionRelativeBudgetMs'],
      kDefaultActionRelativeBudgetMs,
      'actionRelativeBudgetMs',
    );
    final int qn = _clampQuietFrameN(j['quietFrameN']);
    final int bs = _clampBudget(
      j['boundedStabilityBudgetMs'],
      kDefaultBoundedStabilityBudgetMs,
      'boundedStabilityBudgetMs',
    );

    final dynamic rawScreenshot = j['includeScreenshot'];
    final bool includeScreenshot =
        rawScreenshot is bool ? rawScreenshot : false;

    final Map<String, int> extensionBudgets = _parseExtensionBudgets(
      j['extensionBudgets'],
    );

    final dynamic rawCursor = j['errorCursor'];
    final int? errorCursor = rawCursor is int
        ? rawCursor
        : (rawCursor is String ? int.tryParse(rawCursor) : null);

    return ObservationRequest(
      policy: policy,
      actionRelativeBudgetMs: ar,
      quietFrameN: qn,
      boundedStabilityBudgetMs: bs,
      includeScreenshot: includeScreenshot,
      extensionBudgets: extensionBudgets,
      errorCursor: errorCursor,
    );
  }

  static StabilityPolicy _policyFromWire(dynamic raw) {
    if (raw == null) return StabilityPolicy.actionRelative;
    final String token = raw.toString();
    for (final MapEntry<StabilityPolicy, String> e
        in kStabilityPolicyWireNames.entries) {
      if (e.value == token) return e.key;
    }
    throw FormatException(
      'Unknown stability policy: "$token". '
      'Expected one of ${kStabilityPolicyWireNames.values.toList()}.',
    );
  }

  static int _clampBudget(dynamic raw, int fallback, String fieldName) {
    final int value = _toInt(raw, fallback);
    if (value > kMaxBudgetMs) {
      developer.log(
        '$fieldName=$value exceeds kMaxBudgetMs=$kMaxBudgetMs; clamped.',
        name: 'exploration',
      );
      return kMaxBudgetMs;
    }
    if (value < 0) return 0;
    return value;
  }

  static int _clampQuietFrameN(dynamic raw) {
    final int value = _toInt(raw, kDefaultQuietFrameN);
    if (value < 1) return 1;
    return value;
  }

  static int _toInt(dynamic raw, int fallback) {
    if (raw == null) return fallback;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final int? parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static Map<String, int> _parseExtensionBudgets(dynamic raw) {
    if (raw is! Map) return const <String, int>{};
    final Map<String, int> out = <String, int>{};
    raw.forEach((Object? k, Object? v) {
      if (k is String) {
        final int? parsed = v is int
            ? v
            : (v is num
                ? v.toInt()
                : (v is String ? int.tryParse(v) : null));
        if (parsed != null && parsed >= 0) {
          out[k] = parsed;
        }
      }
    });
    return Map<String, int>.unmodifiable(out);
  }
}
