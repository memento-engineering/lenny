import 'package:meta/meta.dart';

/// Wire format for the trajectory JSONL stream (PRD §14).
///
/// Each record serializes to a single JSON object with a `type`
/// discriminator. Field names are snake_case on the wire.

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

  Map<String, dynamic> toJson() => {
        'namespace': namespace,
        'package_version': packageVersion,
        'contract_version': contractVersion,
      };
}

@immutable
class SessionHeader {
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
class TurnRecord {
  final int index;
  final Map<String, dynamic> observation;
  final Map<String, dynamic> stability;
  final Map<String, dynamic> proposedAction;
  final Map<String, dynamic> validation;
  final Map<String, dynamic> executedAction;
  final Map<String, dynamic> diff;
  final String summaryUpdate;
  final Map<String, dynamic> modelMetadata;

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
  });

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
      };
}

@immutable
class PluginDisabledEvent {
  final String namespace;
  final String reason;
  final int turn;

  const PluginDisabledEvent({
    required this.namespace,
    required this.reason,
    required this.turn,
  });

  Map<String, dynamic> toJson() => {
        'type': 'plugin_disabled',
        'namespace': namespace,
        'reason': reason,
        'turn': turn,
      };
}

enum SessionOutcome { done, budgetExhausted, harnessError }

@immutable
class SessionFooter {
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
