import 'package:meta/meta.dart';

/// Wire format for the trajectory JSONL stream (PRD §14).
///
/// Each record serializes to a single JSON object with a `type`
/// discriminator. Field names are snake_case on the wire.

/// Common umbrella for any trajectory record decoded from JSONL.
///
/// All concrete classes ([SessionHeader], [TurnRecord],
/// [PluginDisabledEvent], [SessionFooter], [UnknownTrajectoryRecord])
/// implement this so callers can switch on a single type when
/// hydrating a trajectory stream.
abstract class TrajectoryRecord {
  /// Dispatches on the `type` discriminator. Unknown values yield
  /// [UnknownTrajectoryRecord] rather than throwing — the timeline
  /// must still render the rest of the trajectory if a reader
  /// encounters a record type from a future schema version.
  factory TrajectoryRecord.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'header' => SessionHeader.fromJson(json),
      'turn' => TurnRecord.fromJson(json),
      'plugin_disabled' => PluginDisabledEvent.fromJson(json),
      'footer' => SessionFooter.fromJson(json),
      _ => UnknownTrajectoryRecord(rawType: type?.toString() ?? 'null', raw: json),
    };
  }
}

/// Fallback when the `type` discriminator is absent or unrecognized.
@immutable
class UnknownTrajectoryRecord implements TrajectoryRecord {
  final String rawType;
  final Map<String, dynamic> raw;

  const UnknownTrajectoryRecord({required this.rawType, required this.raw});
}

@immutable
class PluginManifestRecord {
  final String namespace;
  final String packageVersion;
  final String contractVersion;

  const PluginManifestRecord({
    required this.namespace,
    required this.packageVersion,
    required this.contractVersion,
  });

  factory PluginManifestRecord.fromJson(Map<String, dynamic> j) =>
      PluginManifestRecord(
        namespace: j['namespace'] as String,
        packageVersion: j['package_version'] as String,
        contractVersion: j['contract_version'] as String,
      );

  Map<String, dynamic> toJson() => {
        'namespace': namespace,
        'package_version': packageVersion,
        'contract_version': contractVersion,
      };
}

@immutable
class SessionHeader implements TrajectoryRecord {
  final String goal;
  final String agentsMdHash;
  final String buildIdentifier;
  final String modelIdentifier;
  final String harnessVersion;
  final List<PluginManifestRecord> plugins;
  final Map<String, dynamic> config;

  const SessionHeader({
    required this.goal,
    required this.agentsMdHash,
    required this.buildIdentifier,
    required this.modelIdentifier,
    required this.harnessVersion,
    required this.plugins,
    required this.config,
  });

  factory SessionHeader.fromJson(Map<String, dynamic> j) => SessionHeader(
        goal: j['goal'] as String,
        agentsMdHash: j['agents_md_hash'] as String,
        buildIdentifier: j['build_identifier'] as String,
        modelIdentifier: j['model_identifier'] as String,
        harnessVersion: j['harness_version'] as String,
        plugins: [
          for (final p in (j['plugins'] as List? ?? const []))
            PluginManifestRecord.fromJson(p as Map<String, dynamic>),
        ],
        config: Map<String, dynamic>.from(j['config'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'type': 'header',
        'goal': goal,
        'agents_md_hash': agentsMdHash,
        'build_identifier': buildIdentifier,
        'model_identifier': modelIdentifier,
        'harness_version': harnessVersion,
        'plugins': plugins.map((p) => p.toJson()).toList(),
        'config': config,
      };
}

@immutable
class TurnRecord implements TrajectoryRecord {
  final int index;
  final Map<String, dynamic> observation;
  final Map<String, dynamic> stability;
  final Map<String, dynamic> proposedAction;
  final Map<String, dynamic> validation;
  final Map<String, dynamic> executedAction;
  final Map<String, dynamic> diff;
  final String summaryUpdate;
  final Map<String, dynamic> modelMetadata;

  /// Optional provider-side request id (e.g. Anthropic/swift-infer
  /// `message.id`). Round-trips as snake_case `provider_request_id` and
  /// is omitted from [toJson] when null.
  final String? providerRequestId;

  const TurnRecord({
    required this.index,
    required this.observation,
    required this.stability,
    required this.proposedAction,
    required this.validation,
    required this.executedAction,
    required this.diff,
    required this.summaryUpdate,
    required this.modelMetadata,
    this.providerRequestId,
  });

  factory TurnRecord.fromJson(Map<String, dynamic> j) => TurnRecord(
        index: (j['index'] as num).toInt(),
        observation: Map<String, dynamic>.from(j['observation'] as Map? ?? const {}),
        stability: Map<String, dynamic>.from(j['stability'] as Map? ?? const {}),
        proposedAction:
            Map<String, dynamic>.from(j['proposed_action'] as Map? ?? const {}),
        validation: Map<String, dynamic>.from(j['validation'] as Map? ?? const {}),
        executedAction:
            Map<String, dynamic>.from(j['executed_action'] as Map? ?? const {}),
        diff: Map<String, dynamic>.from(j['diff'] as Map? ?? const {}),
        summaryUpdate: (j['summary_update'] as String?) ?? '',
        modelMetadata:
            Map<String, dynamic>.from(j['model_metadata'] as Map? ?? const {}),
        providerRequestId: j['provider_request_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': 'turn',
        'index': index,
        'observation': observation,
        'stability': stability,
        'proposed_action': proposedAction,
        'validation': validation,
        'executed_action': executedAction,
        'diff': diff,
        'summary_update': summaryUpdate,
        'model_metadata': modelMetadata,
        if (providerRequestId != null)
          'provider_request_id': providerRequestId,
      };
}

@immutable
class PluginDisabledEvent implements TrajectoryRecord {
  final String namespace;
  final String reason;
  final int turn;

  const PluginDisabledEvent({
    required this.namespace,
    required this.reason,
    required this.turn,
  });

  factory PluginDisabledEvent.fromJson(Map<String, dynamic> j) =>
      PluginDisabledEvent(
        namespace: j['namespace'] as String,
        reason: j['reason'] as String,
        turn: (j['turn'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'type': 'plugin_disabled',
        'namespace': namespace,
        'reason': reason,
        'turn': turn,
      };
}

enum SessionOutcome { done, budgetExhausted, harnessError }

@immutable
class SessionFooter implements TrajectoryRecord {
  final SessionOutcome outcome;
  final String finalSummary;
  final int totalTurns;
  final int totalDurationMs;
  final String? harnessError;

  const SessionFooter({
    required this.outcome,
    required this.finalSummary,
    required this.totalTurns,
    required this.totalDurationMs,
    this.harnessError,
  });

  factory SessionFooter.fromJson(Map<String, dynamic> j) => SessionFooter(
        outcome: switch (j['outcome'] as String?) {
          'done' => SessionOutcome.done,
          'budget_exhausted' => SessionOutcome.budgetExhausted,
          'harness_error' => SessionOutcome.harnessError,
          _ => SessionOutcome.harnessError,
        },
        finalSummary: (j['final_summary'] as String?) ?? '',
        totalTurns: (j['total_turns'] as num?)?.toInt() ?? 0,
        totalDurationMs: (j['total_duration_ms'] as num?)?.toInt() ?? 0,
        harnessError: j['harness_error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': 'footer',
        'outcome': switch (outcome) {
          SessionOutcome.done => 'done',
          SessionOutcome.budgetExhausted => 'budget_exhausted',
          SessionOutcome.harnessError => 'harness_error',
        },
        'final_summary': finalSummary,
        'total_turns': totalTurns,
        'total_duration_ms': totalDurationMs,
        if (harnessError != null) 'harness_error': harnessError,
      };
}
