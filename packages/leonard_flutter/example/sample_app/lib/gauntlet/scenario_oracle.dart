import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

/// Ground-truth + progress for one gauntlet scenario.
///
/// Read by the gauntlet test harness over the `ext.gauntlet.oracle`
/// VM-service back-channel. This back-channel is registered DELIBERATELY
/// OUTSIDE leonard's `ext.flutter.exploration.*` namespace and never
/// contributes an observation fragment, so the driving agent cannot read
/// the answer out of its own observation bundle — the oracle is a private
/// side-channel for the grader, not part of the app the agent perceives.
@immutable
class ScenarioOracleState {
  const ScenarioOracleState({
    required this.scenarioId,
    this.expected = const <String, Object?>{},
    this.goalReached = false,
    this.lastTapFraction,
  });

  /// Stable id, e.g. `settle/decorative-motion`.
  final String scenarioId;

  /// Hidden ground truth the grader compares the agent's answer against
  /// (e.g. `{count: 20}`, `{code: 'AZ-4471'}`). Never surfaced to the agent.
  final Map<String, Object?> expected;

  /// Flips true when the scenario's success action occurs in-app (e.g. the
  /// correct button is tapped). Action-oracle scenarios assert on this.
  final bool goalReached;

  /// For vision scenarios: the last tap recorded over the target image,
  /// normalised to 0..1 of the image's painted box. Compared against a
  /// committed fractional bounding box.
  final Offset? lastTapFraction;

  ScenarioOracleState copyWith({bool? goalReached, Offset? lastTapFraction}) {
    return ScenarioOracleState(
      scenarioId: scenarioId,
      expected: expected,
      goalReached: goalReached ?? this.goalReached,
      lastTapFraction: lastTapFraction ?? this.lastTapFraction,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'scenario_id': scenarioId,
    'expected': expected,
    'goal_reached': goalReached,
    'last_tap_fraction': lastTapFraction == null
        ? null
        : <String, double>{'x': lastTapFraction!.dx, 'y': lastTapFraction!.dy},
  };
}

/// The currently-mounted scenario's oracle, or null when no scenario is
/// active. Mutated only by [ScenarioHost] lifecycle + the `mark*` helpers.
final ValueNotifier<ScenarioOracleState?> gauntletOracle =
    ValueNotifier<ScenarioOracleState?>(null);

bool _extensionRegistered = false;

/// Registers the `ext.gauntlet.oracle` VM-service back-channel.
///
/// Debug-only by construction: the body runs inside an `assert`, so the
/// whole thing is tree-shaken out of profile/release builds. Idempotent.
///
/// Supported params:
///   * (none) / `op=get`  -> `{active, oracle}`
///   * `op=reset`         -> clears progress (goal_reached / tap) but keeps
///                           the active scenario + its expected ground truth,
///                           then returns the reset state.
void registerGauntletOracleExtension() {
  assert(() {
    if (_extensionRegistered) return true;
    _extensionRegistered = true;
    developer.registerExtension('ext.gauntlet.oracle', (
      String method,
      Map<String, String> params,
    ) async {
      final String op = params['op'] ?? 'get';
      if (op == 'reset') {
        final ScenarioOracleState? s = gauntletOracle.value;
        if (s != null) {
          gauntletOracle.value = ScenarioOracleState(
            scenarioId: s.scenarioId,
            expected: s.expected,
          );
        }
      }
      final ScenarioOracleState? s = gauntletOracle.value;
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object?>{
          'active': s != null,
          'oracle': s?.toJson(),
        }),
      );
    });
    return true;
  }());
}

/// Marks [id] active with its hidden [expected] ground truth.
void activateScenario(String id, {Map<String, Object?> expected = const {}}) {
  gauntletOracle.value = ScenarioOracleState(
    scenarioId: id,
    expected: expected,
  );
}

/// Clears the active scenario if it is still [id] (guards against a
/// late dispose racing the next scenario's mount).
void deactivateScenario(String id) {
  if (gauntletOracle.value?.scenarioId == id) {
    gauntletOracle.value = null;
  }
}

/// Records that [id]'s success action occurred.
void markGoalReached(String id) {
  final ScenarioOracleState? s = gauntletOracle.value;
  if (s != null && s.scenarioId == id) {
    gauntletOracle.value = s.copyWith(goalReached: true);
  }
}

/// Records a normalised (0..1) tap over [id]'s target image.
void recordTapFraction(String id, Offset fraction) {
  final ScenarioOracleState? s = gauntletOracle.value;
  if (s != null && s.scenarioId == id) {
    gauntletOracle.value = s.copyWith(lastTapFraction: fraction);
  }
}

/// Wraps a scenario screen, owning the activate/deactivate lifecycle so
/// individual scenarios stay declarative. Mount activates [id] with its
/// [expected] ground truth; unmount clears it.
class ScenarioHost extends StatefulWidget {
  const ScenarioHost({
    super.key,
    required this.id,
    required this.child,
    this.expected = const <String, Object?>{},
  });

  final String id;
  final Map<String, Object?> expected;
  final Widget child;

  @override
  State<ScenarioHost> createState() => _ScenarioHostState();
}

class _ScenarioHostState extends State<ScenarioHost> {
  @override
  void initState() {
    super.initState();
    activateScenario(widget.id, expected: widget.expected);
  }

  @override
  void dispose() {
    deactivateScenario(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
