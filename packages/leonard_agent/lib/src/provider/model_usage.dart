/// Provider-reported usage for one model call, and the price table that turns
/// a run's token totals into an estimated cost (lenny#178).
library;

import 'package:meta/meta.dart';

/// What the provider reported about one model call.
///
/// Every field is nullable: a provider that does not report a figure leaves
/// it null, and consumers treat null as "unknown", never as zero. Latency is
/// not here — the loop driver measures it uniformly for every provider.
@immutable
class ModelCallUsage {
  /// Creates a usage record for one call.
  const ModelCallUsage({
    this.provider,
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.timeToFirstTokenMs,
  });

  /// Decodes a usage record from [toJson]'s shape.
  factory ModelCallUsage.fromJson(Map<String, dynamic> json) => ModelCallUsage(
    provider: json['provider'] as String?,
    model: json['model'] as String?,
    inputTokens: (json['input_tokens'] as num?)?.toInt(),
    outputTokens: (json['output_tokens'] as num?)?.toInt(),
    timeToFirstTokenMs: (json['time_to_first_token_ms'] as num?)?.toInt(),
  );

  /// Provider family: `anthropic`, `openai` or `swift-infer`.
  final String? provider;

  /// The model id the call was made against.
  final String? model;

  /// Prompt tokens the provider billed for this call.
  final int? inputTokens;

  /// Completion tokens the provider billed for this call, reasoning included.
  final int? outputTokens;

  /// Milliseconds from sending the request to the first streamed content
  /// (thinking, text or a tool call).
  final int? timeToFirstTokenMs;

  /// Encodes this record, omitting unknown fields.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (provider != null) 'provider': provider,
    if (model != null) 'model': model,
    if (inputTokens != null) 'input_tokens': inputTokens,
    if (outputTokens != null) 'output_tokens': outputTokens,
    if (timeToFirstTokenMs != null)
      'time_to_first_token_ms': timeToFirstTokenMs,
  };

  @override
  bool operator ==(Object other) =>
      other is ModelCallUsage &&
      provider == other.provider &&
      model == other.model &&
      inputTokens == other.inputTokens &&
      outputTokens == other.outputTokens &&
      timeToFirstTokenMs == other.timeToFirstTokenMs;

  @override
  int get hashCode => Object.hash(
    provider,
    model,
    inputTokens,
    outputTokens,
    timeToFirstTokenMs,
  );
}

/// A per-million-token price in US dollars.
@immutable
class ModelPrice {
  /// Creates a price of [inputPerMTok] and [outputPerMTok] dollars per
  /// million tokens.
  const ModelPrice({required this.inputPerMTok, required this.outputPerMTok});

  /// Dollars per million input tokens.
  final double inputPerMTok;

  /// Dollars per million output tokens.
  final double outputPerMTok;

  /// The estimated cost of [inputTokens] and [outputTokens], in dollars.
  double cost({required int inputTokens, required int outputTokens}) =>
      (inputTokens * inputPerMTok + outputTokens * outputPerMTok) / 1e6;
}

/// List prices for the hosted models the CLI tiers run, as published on the
/// providers' pricing pages on [ModelPricing.defaultsAsOf]. Standard (not
/// batch) rates; cache rates are not used until cache tokens are reported.
const Map<String, ModelPrice> kDefaultModelPrices = <String, ModelPrice>{
  'claude-opus-5-5': ModelPrice(inputPerMTok: 4, outputPerMTok: 20),
  'claude-sonnet-5-5': ModelPrice(inputPerMTok: 2, outputPerMTok: 10),
  'claude-opus-4-6': ModelPrice(inputPerMTok: 5, outputPerMTok: 25),
  'claude-sonnet-4-6': ModelPrice(inputPerMTok: 3, outputPerMTok: 15),
  'gpt-5': ModelPrice(inputPerMTok: 1.25, outputPerMTok: 10),
  'gpt-5-mini': ModelPrice(inputPerMTok: 0.25, outputPerMTok: 2),
};

/// Resolves the price a run is costed at.
///
/// An [override] applies to every model, local ones included (so an operator
/// can price owned hardware). Without one, a hosted model is looked up in
/// [prices]; a `swift-infer` model or an unknown id has no price, and its cost
/// is reported as unset rather than zero.
@immutable
class ModelPricing {
  /// Creates a pricing policy.
  const ModelPricing({
    this.prices = kDefaultModelPrices,
    this.override,
    this.asOf = defaultsAsOf,
  });

  /// The built-in table with no override.
  static const ModelPricing defaults = ModelPricing();

  /// The date [kDefaultModelPrices] was checked against the providers'
  /// pricing pages.
  static const String defaultsAsOf = '2026-10-17';

  /// Per-model list prices.
  final Map<String, ModelPrice> prices;

  /// A price applied to every model, replacing the table.
  final ModelPrice? override;

  /// The date the [prices] table was last checked.
  final String asOf;

  /// The price for [model] served by [provider], or null when unset.
  ModelPrice? priceFor({String? provider, String? model}) {
    if (override != null) return override;
    if (provider == 'swift-infer' || model == null) return null;
    return prices[model];
  }

  /// Where [priceFor] got its answer, for the footer.
  String get source => override != null ? 'override' : 'built-in $asOf';
}
