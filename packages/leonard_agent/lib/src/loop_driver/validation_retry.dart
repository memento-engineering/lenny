/// Decide+validate retry helper (PRD §10 steps 6+7, §17).
///
/// Two independent retry budgets:
///   * **Schema budget = 1**. On [SchemaRejection] from the provider,
///     retry once with the schema validation error appended as a
///     synthetic [UserTurn] to a snapshot copy. A second
///     `SchemaRejection` throws [SchemaExhausted].
///   * **Validator budget = 3**. On [ValidationReject] from the
///     validator, retry up to three times against the same observation
///     with the rejection's structured JSON appended as a synthetic
///     [UserTurn]. The fourth reject throws [InvalidActionExhausted].
///
/// "Splicing" is implemented by [ConversationSnapshot.withAppended]
/// — the base snapshot is left immutable so the caller can re-use it.
library;

import 'package:meta/meta.dart';

import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../provider/action_schema.dart';
import '../provider/model_provider.dart';
import '../provider/types.dart';
import '../validation/action_validator.dart';
import '../validation/result.dart';

/// Maximum number of validator retries before giving up. PRD §17.
const int _kDefaultMaxValidationRetries = 3;

/// Result of a successful [decideAndValidate] call.
@immutable
class ValidationLoopResult {
  const ValidationLoopResult({
    required this.decision,
    required this.retries,
    required this.rejections,
    required this.schemaRetries,
  });

  /// The decision the validator accepted.
  final ModelDecision decision;

  /// How many validator retries were spent before [decision] passed
  /// (0..[_kDefaultMaxValidationRetries]).
  final int retries;

  /// Validator rejection messages (in retry order). Length == [retries].
  final List<String> rejections;

  /// How many schema retries were spent (0 or 1).
  final int schemaRetries;
}

/// Thrown by [decideAndValidate] when the validator rejected the model
/// output 3 times (PRD §17). Carries the structured rejection messages
/// the driver writes into the failed-turn record.
class InvalidActionExhausted implements Exception {
  const InvalidActionExhausted(this.rejections);

  /// Validator rejection messages, in chronological order.
  final List<String> rejections;

  @override
  String toString() =>
      'InvalidActionExhausted(${rejections.length} rejections)';
}

/// Thrown by [decideAndValidate] when the provider threw
/// [SchemaRejection] twice in a row (PRD §17 schema budget = 1).
class SchemaExhausted implements Exception {
  const SchemaExhausted(this.cause);
  final SchemaRejection cause;

  @override
  String toString() => 'SchemaExhausted: ${cause.validationError}';
}

/// Run one decide-and-validate cycle for a single turn against a
/// chat-shape [ConversationSnapshot].
///
/// Schema/validator retries append synthetic [UserTurn]s carrying a
/// `toolResult` map (`{schema_error: ...}` or `{validation_error: ...}`)
/// to a copy of [baseSnapshot] via [ConversationSnapshot.withAppended].
/// The base snapshot is left untouched.
///
/// On success returns a [ValidationLoopResult] with the accepted
/// [ModelDecision]. On exhausted budgets throws either
/// [InvalidActionExhausted] or [SchemaExhausted] — both translate to
/// failed turns at the [LoopDriver] layer.
///
/// [maxValidationRetries] defaults to 3 (PRD §17). Schema retries are
/// always one (PRD §17).
Future<ValidationLoopResult> decideAndValidate({
  required ModelProvider provider,
  required ConversationSnapshot baseSnapshot,
  required ActionSchema schema,
  required ActionValidator validator,
  required Observation observation,
  required List<ToolDescriptor> mergedTools,
  int maxValidationRetries = _kDefaultMaxValidationRetries,
}) async {
  final List<String> rejections = <String>[];
  ConversationSnapshot snapshot = baseSnapshot;

  int schemaRetries = 0;
  Future<ModelDecision> decideWithSchemaRetry() async {
    Future<ModelDecision> attempt() => provider.decide(snapshot, schema);
    try {
      return await attempt();
    } on SchemaRejection catch (first) {
      if (schemaRetries >= 1) {
        throw SchemaExhausted(first);
      }
      schemaRetries = 1;
      snapshot = snapshot.withAppended(UserTurn(
        observation: Observation.empty(),
        diff: ObservationDiff.empty(),
        toolResult: <String, dynamic>{
          'schema_error': first.validationError,
        },
      ));
      try {
        return await attempt();
      } on SchemaRejection catch (second) {
        throw SchemaExhausted(second);
      }
    }
  }

  for (int attempt = 0; attempt <= maxValidationRetries; attempt++) {
    final ModelDecision decision = await decideWithSchemaRetry();
    final ValidationResult result = validator.validate(
      decision.action,
      observation,
      mergedTools,
    );
    if (result is ValidationOk) {
      return ValidationLoopResult(
        decision: decision,
        retries: rejections.length,
        rejections: List<String>.unmodifiable(rejections),
        schemaRetries: schemaRetries,
      );
    }
    final ValidationReject reject = result as ValidationReject;
    rejections.add(reject.toModelMessage());
    if (rejections.length >= maxValidationRetries + 1) {
      throw InvalidActionExhausted(List<String>.unmodifiable(rejections));
    }
    snapshot = snapshot.withAppended(UserTurn(
      observation: Observation.empty(),
      diff: ObservationDiff.empty(),
      toolResult: <String, dynamic>{
        'validation_error': reject.toModelMessage(),
      },
    ));
  }
  throw StateError('decideAndValidate fell through retry loop');
}
