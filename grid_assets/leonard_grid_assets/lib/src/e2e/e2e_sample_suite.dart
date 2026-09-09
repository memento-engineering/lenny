/// Private sample-app scenario composition over the single E2E operation.
library;

import 'package:path/path.dart' as p;

import 'e2e_service.dart';
import 'e2e_session.dart';

/// Sample application path relative to the repository root.
const String kLeonardSampleAppDir =
    'packages/leonard_flutter/example/sample_app';

/// One pinned sample-suite scenario.
class E2eScenario {
  /// Creates a scenario.
  const E2eScenario({
    required this.name,
    required this.goal,
    required this.doneReasonPattern,
    required this.doneEvidencePattern,
    required this.expectation,
  });

  /// Stable scenario name.
  final String name;

  /// Credential-aware goal.
  final String goal;

  /// Exact `core.done` reason pattern.
  final String doneReasonPattern;

  /// Exact `core.done` evidence pattern.
  final String doneEvidencePattern;

  /// Expected final observation.
  final E2eObservationExpectation expectation;
}

/// The four ordered lenny sample-app scenarios.
const List<E2eScenario> kLeonardSampleSuite = <E2eScenario>[
  E2eScenario(
    name: 'login',
    goal:
        'Log in by typing the email demo@example.com and password password, '
        'then sign in',
    doneReasonPattern: r'.*(?:[Ll]ogged in|[Ss]igned in).*',
    doneEvidencePattern: 'Home|home',
    expectation: E2eObservationExpectation(route: 'home'),
  ),
  E2eScenario(
    name: 'navigation',
    goal:
        'Sign in with email demo@example.com and password password, then open '
        'the Settings screen',
    doneReasonPattern: r'.*[Ss]ettings.*',
    doneEvidencePattern: 'Settings|settings',
    expectation: E2eObservationExpectation(route: 'settings'),
  ),
  E2eScenario(
    name: 'state_change',
    goal:
        'Sign in with email demo@example.com and password password, then open '
        'Settings and turn on Dark Theme',
    doneReasonPattern: r'.*[Dd]ark [Tt]heme.*(?:on|enabled).*',
    doneEvidencePattern: 'Dark Theme',
    expectation: E2eObservationExpectation(
      semanticsLabel: 'Dark Theme',
      semanticsState: 'on',
    ),
  ),
  E2eScenario(
    name: 'scroll',
    goal:
        'Sign in with email demo@example.com and password password, open the '
        'Terms screen, scroll down to the bottom, and turn on Accept Terms',
    doneReasonPattern: r'.*[Aa]ccept [Tt]erms.*(?:on|enabled|accepted).*',
    doneEvidencePattern: 'Accept Terms',
    expectation: E2eObservationExpectation(
      semanticsLabel: 'Accept Terms',
      semanticsState: 'on',
    ),
  ),
];

/// One named scenario result.
class E2eScenarioVerdict {
  /// Creates a scenario result.
  const E2eScenarioVerdict({required this.scenario, required this.verdict});

  /// Scenario definition.
  final E2eScenario scenario;

  /// Typed single-session verdict.
  final E2eVerdict verdict;

  /// Encodes the scenario name beside the session fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'scenario': scenario.name,
    ...verdict.toJson(),
  };
}

/// Aggregate result of the ordered four-scenario suite.
class E2eSuiteVerdict {
  /// Creates an aggregate suite verdict.
  E2eSuiteVerdict({
    required this.status,
    required this.model,
    required List<E2eScenarioVerdict> scenarios,
  }) : scenarios = List<E2eScenarioVerdict>.unmodifiable(scenarios);

  /// Pass only when every scenario passed.
  final E2eVerdictStatus status;

  /// Requested provider tier.
  final E2eModel model;

  /// All four typed results in execution order.
  final List<E2eScenarioVerdict> scenarios;

  /// Whether all four scenarios passed.
  bool get passed => status == E2eVerdictStatus.pass;

  /// Encodes the single JSON report emitted by the Command.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'model': model.cliName,
    'scenarios': scenarios
        .map((E2eScenarioVerdict verdict) => verdict.toJson())
        .toList(growable: false),
  };
}

/// Locates the sample app beneath the nearest ancestor that contains it.
Future<String?> findLeonardSampleAppDir(
  E2eRuntime runtime, {
  String? startingDirectory,
}) async {
  var directory = p.normalize(startingDirectory ?? runtime.currentDirectory);
  while (true) {
    final String candidate = p.join(directory, kLeonardSampleAppDir);
    if (await runtime.directoryExists(candidate)) return candidate;
    final String parent = p.dirname(directory);
    if (parent == directory) return null;
    directory = parent;
  }
}

/// Sequentially runs the four scenarios through [E2eService.runSession].
Future<E2eSuiteVerdict> performE2eSampleSuite(
  E2eService service, {
  required String appDir,
  required E2eModel model,
  String? modelId,
  String? device,
  required List<String> extensions,
  required List<String> cliPrefix,
}) async {
  final List<E2eScenarioVerdict> results = <E2eScenarioVerdict>[];
  for (final E2eScenario scenario in kLeonardSampleSuite) {
    final E2eVerdict verdict = await service.runSession(
      E2eSessionRequest(
        goal: scenario.goal,
        appDir: appDir,
        model: model,
        modelId: modelId,
        device: device,
        extensions: extensions,
        cliPrefix: cliPrefix,
        doneReasonPattern: scenario.doneReasonPattern,
        doneEvidencePattern: scenario.doneEvidencePattern,
        expectation: scenario.expectation,
      ),
    );
    results.add(E2eScenarioVerdict(scenario: scenario, verdict: verdict));
  }
  return E2eSuiteVerdict(
    status: results.every((E2eScenarioVerdict result) => result.verdict.passed)
        ? E2eVerdictStatus.pass
        : E2eVerdictStatus.fail,
    model: model,
    scenarios: results,
  );
}
