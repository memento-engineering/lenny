/// Decide+validate retry helper (PRD §10 steps 6+7, §17).
///
/// Two independent retry budgets:
///   * **Schema budget = 1**. On [SchemaRejection] from the provider,
///     retry once with the schema validation error spliced into the
///     prompt. A second `SchemaRejection` throws [SchemaExhausted].
///   * **Validator budget = 3**. On [ValidationReject] from the
///     validator, retry up to three times against the same observation
///     with the rejection's structured JSON spliced into the prompt.
///     The fourth reject throws [InvalidActionExhausted].
///
/// "Splicing" is implemented by appending the error message as an
/// extra user-message entry on a freshly-constructed [PromptPayload]
/// — the base prompt is left immutable so the caller can re-use it.
library;

import 'package:meta/meta.dart';

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
/// output [PluginFailureTracker.autoDisableThreshold]-equivalent times
/// (default 3 — PRD §17). Carries the structured rejection messages
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

/// Run one decide-and-validate cycle for a single turn.
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
  required PromptPayload basePrompt,
  required ActionSchema schema,
  required ActionValidator validator,
  required Observation observation,
  required List<ToolDescriptor> mergedTools,
  int maxValidationRetries = _kDefaultMaxValidationRetries,
}) async {
  final List<String> rejections = <String>[];
  PromptPayload prompt = basePrompt;

  // --- one decide call (with at most one schema retry) ---
  // schemaRetries accumulates across the lifetime of this call (PRD §17
  // schema budget = 1 *total*, not per-validator-attempt).
  int schemaRetries = 0;
  Future<ModelDecision> decideWithSchemaRetry() async {
    Future<ModelDecision> attempt() => provider.decide(prompt, schema);
    try {
      return await attempt();
    } on SchemaRejection catch (first) {
      if (schemaRetries >= 1) {
        // Already used our one schema retry on a previous attempt —
        // a further schema violation is fatal.
        throw SchemaExhausted(first);
      }
      schemaRetries = 1;
      prompt = _withRetryMessage(
        prompt,
        'schema_violation: ${first.validationError}',
      );
      try {
        return await attempt();
      } on SchemaRejection catch (second) {
        throw SchemaExhausted(second);
      }
    }
  }

  // --- the validator-retry outer loop ---
  // The decide() call always happens fresh inside the loop so that any
  // additional rejection messages spliced into [prompt] are visible to
  // the model on the next attempt.
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
      // We've exceeded the budget — throw with the collected messages.
      throw InvalidActionExhausted(List<String>.unmodifiable(rejections));
    }
    prompt = _withRetryMessage(prompt, reject.toModelMessage());
  }
  // Loop exits via either return or throw above; this is unreachable.
  throw StateError('decideAndValidate fell through retry loop');
}

PromptPayload _withRetryMessage(PromptPayload base, String message) {
  return PromptPayload(
    systemMessage: base.systemMessage,
    userMessages: List<Map<String, dynamic>>.unmodifiable(<Map<String, dynamic>>[
      ...base.userMessages,
      <String, dynamic>{
        'type': 'text',
        'text': 'previous_attempt_rejected: $message',
      },
    ]),
    tools: base.tools,
  );
}
