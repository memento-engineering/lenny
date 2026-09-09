/// Typed request and verdict values for Leonard live-device E2E sessions.
library;

/// Leonard's supported provider tiers.
enum E2eModel {
  /// Anthropic Claude.
  claude('claude', 'claude'),

  /// The local swift-infer Qwen provider.
  qwenMlx('qwen-mlx', 'qwenMlx'),

  /// OpenAI.
  openai('openai', 'openai');

  const E2eModel(this.cliName, this.trajectoryIdentifier);

  /// Parses a command-line model name, or returns null when unsupported.
  static E2eModel? tryParse(String value) {
    final String normalized = value.trim();
    for (final E2eModel model in values) {
      if (model.cliName == normalized) return model;
    }
    return null;
  }

  /// Name accepted by `leonard_cli --model`.
  final String cliName;

  /// Identifier written to `SessionHeader.modelIdentifier`.
  final String trajectoryIdentifier;
}

/// A route and/or semantics assertion over the final typed observation.
class E2eObservationExpectation {
  /// Creates an expectation.
  ///
  /// [semanticsLabel] and [semanticsState] must either both be supplied or
  /// both be absent.
  const E2eObservationExpectation({
    this.route,
    this.semanticsLabel,
    this.semanticsState,
  }) : assert(
         (semanticsLabel == null) == (semanticsState == null),
         'semantics label and state must be paired',
       );

  /// Required route name, when route evidence is requested.
  final String? route;

  /// Required semantics label, paired with [semanticsState].
  final String? semanticsLabel;

  /// Required state on the node named by [semanticsLabel].
  final String? semanticsState;

  /// Whether no final-observation assertion was requested.
  bool get isEmpty => route == null && semanticsLabel == null;
}

/// One immutable live-device session request.
class E2eSessionRequest {
  /// Creates a session request.
  E2eSessionRequest({
    required this.goal,
    required this.appDir,
    this.model = E2eModel.claude,
    this.modelId,
    this.device,
    List<String> extensions = const <String>['router', 'riverpod', 'dio'],
    List<String> cliPrefix = const <String>['dart', 'run', 'leonard_cli'],
    this.doneReasonPattern,
    this.doneEvidencePattern,
    this.expectation = const E2eObservationExpectation(),
  }) : extensions = List<String>.unmodifiable(extensions),
       cliPrefix = List<String>.unmodifiable(cliPrefix);

  /// Goal the agent drives toward.
  final String goal;

  /// Absolute Flutter application directory.
  final String appDir;

  /// Provider tier.
  final E2eModel model;

  /// Optional exact model id.
  final String? modelId;

  /// Optional Flutter device id.
  final String? device;

  /// Leonard extension namespaces.
  final List<String> extensions;

  /// Executable plus leading arguments used to invoke `leonard_cli`.
  final List<String> cliPrefix;

  /// Optional `core.done` reason regular expression.
  final String? doneReasonPattern;

  /// Optional `core.done` evidence regular expression.
  final String? doneEvidencePattern;

  /// Assertions over the final typed observation.
  final E2eObservationExpectation expectation;
}

/// Splits a shell-style executable prefix into argv without invoking a shell.
///
/// Single and double quotes plus backslash escaping are supported. Environment
/// expansion and command substitution are deliberately not performed.
List<String> parseE2eCliPrefix(String source) {
  final List<String> words = <String>[];
  final StringBuffer word = StringBuffer();
  String? quote;
  var escaping = false;
  var hasToken = false;
  for (var index = 0; index < source.length; index++) {
    final String char = source[index];
    if (escaping) {
      word.write(char);
      hasToken = true;
      escaping = false;
    } else if (char == r'\' && quote != "'") {
      escaping = true;
      hasToken = true;
    } else if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        word.write(char);
        hasToken = true;
      }
    } else if (char == "'" || char == '"') {
      quote = char;
      hasToken = true;
    } else if (char.trim().isEmpty) {
      if (hasToken) {
        words.add(word.toString());
        word.clear();
        hasToken = false;
      }
    } else {
      word.write(char);
      hasToken = true;
    }
  }
  if (quote != null || escaping) {
    throw const FormatException('CLI contains an unterminated quote or escape');
  }
  if (hasToken) words.add(word.toString());
  return words;
}

/// Stable machine-readable reasons a session did not pass.
enum E2eFailureCode {
  /// The request was incomplete or internally inconsistent.
  invalidRequest('invalid_request'),

  /// `flutter devices --machine` failed or returned malformed JSON.
  deviceDiscovery('device_discovery'),

  /// No unique eligible iOS device could be selected.
  deviceSelection('device_selection'),

  /// The selected iOS device is connected wirelessly.
  wirelessDevice('wireless_device'),

  /// The app directory is not an absolute Flutter iOS application path.
  appDirectory('app_directory'),

  /// A provider credential or endpoint is absent.
  missingEnvironment('missing_environment'),

  /// The swift-infer model catalog could not clear the requested model.
  modelCatalog('model_catalog'),

  /// The Flutter application could not be launched or become ready.
  launch('launch'),

  /// The Leonard child process could not be invoked.
  driverInvocation('driver_invocation'),

  /// No trajectory file was produced.
  trajectoryMissing('trajectory_missing'),

  /// The trajectory is not valid typed JSONL.
  malformedTrajectory('malformed_trajectory'),

  /// Required typed records are absent, duplicated, or unknown.
  trajectoryShape('trajectory_shape'),

  /// The header identifies a different provider tier.
  modelMismatch('model_mismatch'),

  /// The typed footer outcome is not `done`.
  outcomeNotDone('outcome_not_done'),

  /// Executed action failures exceeded the one-recovered-failure allowance.
  actionFailure('action_failure'),

  /// The final three turns repeat the same tool and arguments.
  terminalLoop('terminal_loop'),

  /// The final observation does not contain the requested evidence.
  expectationUnmet('expectation_unmet'),

  /// A requested extension disabled itself during the run.
  extensionDisabled('extension_disabled'),

  /// An unexpected runtime failure escaped a phase boundary.
  unexpected('unexpected');

  const E2eFailureCode(this.wireName);

  /// Stable JSON name.
  final String wireName;
}

/// Overall session status.
enum E2eVerdictStatus {
  /// Every deterministic assertion passed.
  pass,

  /// At least one deterministic assertion failed.
  fail,
}

/// Structured deterministic result of one Leonard E2E session.
class E2eVerdict {
  /// Creates a verdict over typed trajectory and runtime evidence.
  E2eVerdict({
    required this.status,
    required List<E2eFailureCode> failureCodes,
    required this.model,
    required this.device,
    required this.turns,
    required this.durationMilliseconds,
    required this.trajectoryPath,
    required this.driverExitStatus,
    required this.providerRequestId,
    required this.actionFailures,
    required Map<String, Object?> expectationEvidence,
  }) : failureCodes = List<E2eFailureCode>.unmodifiable(failureCodes),
       expectationEvidence = Map<String, Object?>.unmodifiable(
         expectationEvidence,
       );

  /// Creates a failed phase verdict before typed inspection completes.
  factory E2eVerdict.failed({
    required E2eFailureCode code,
    required E2eModel model,
    required int durationMilliseconds,
    String? device,
    String trajectoryPath = '',
    int? driverExitStatus,
    Map<String, Object?> evidence = const <String, Object?>{},
  }) => E2eVerdict(
    status: E2eVerdictStatus.fail,
    failureCodes: <E2eFailureCode>[code],
    model: model,
    device: device,
    turns: 0,
    durationMilliseconds: durationMilliseconds,
    trajectoryPath: trajectoryPath,
    driverExitStatus: driverExitStatus,
    providerRequestId: null,
    actionFailures: 0,
    expectationEvidence: evidence,
  );

  /// Deterministic pass/fail status.
  final E2eVerdictStatus status;

  /// Stable failure classifications. Empty for a pass.
  final List<E2eFailureCode> failureCodes;

  /// Requested provider tier.
  final E2eModel model;

  /// Selected Flutter device id, when preflight reached device selection.
  final String? device;

  /// Number of typed turn records.
  final int turns;

  /// Typed footer duration, or elapsed phase duration before inspection.
  final int durationMilliseconds;

  /// Explicit trajectory path for this run.
  final String trajectoryPath;

  /// Child Leonard process exit status, retained as receipt data only.
  final int? driverExitStatus;

  /// Latest non-null provider request id in the typed turns.
  final String? providerRequestId;

  /// Count of typed executed actions whose result has `ok == false`.
  final int actionFailures;

  /// Requested and observed final-state evidence.
  final Map<String, Object?> expectationEvidence;

  /// Whether every assertion passed.
  bool get passed => status == E2eVerdictStatus.pass;

  /// Encodes the stable JSON object emitted by the Command and circuit.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'failure_codes': failureCodes
        .map((E2eFailureCode code) => code.wireName)
        .toList(growable: false),
    'model': model.cliName,
    'device': device,
    'turns': turns,
    'duration_ms': durationMilliseconds,
    'trajectory_path': trajectoryPath,
    'driver_exit_status': driverExitStatus,
    'provider_request_id': providerRequestId,
    'action_failures': actionFailures,
    'expectation_evidence': expectationEvidence,
  };
}

/// A typed failure raised by a public phase and folded by `runSession`.
class E2ePhaseFailure implements Exception {
  /// Creates a phase failure with stable [code] and diagnostic [message].
  const E2ePhaseFailure(this.code, this.message);

  /// Machine-readable category.
  final E2eFailureCode code;

  /// Human-readable diagnostic for logs and capability failures.
  final String message;

  @override
  String toString() => message;
}
