/// Renders an [Observation] to a provider-agnostic text representation.
///
/// Pulled out as an interface so the conversation builder can swap in
/// alternative renderings (compact, markdown, etc.) without touching
/// provider code. [JsonObservationRenderer] is the canonical default
/// used by [ConversationBuilder].
library;

import 'dart:convert';

import '../observation/models.dart';

/// Interface used by `ConversationBuilder` to flatten an [Observation]
/// into the text body of a `UserTurn` for any provider.
abstract interface class ObservationRenderer {
  String render(Observation obs);
}

/// Renders [Observation] as compact JSON. Top-level keys are stable
/// (`core`, `plugins`, `stability`) so a `jsonDecode` of the output
/// is structurally identical to the wire format the binding produced
/// (modulo screenshot, which the renderer omits — providers add the
/// image as a separate content part).
class JsonObservationRenderer implements ObservationRenderer {
  const JsonObservationRenderer();

  @override
  String render(Observation obs) {
    final List<String> sortedPluginKeys = obs.plugins.keys.toList()..sort();
    return jsonEncode(<String, dynamic>{
      'core': obs.core.toJson(),
      'plugins': <String, dynamic>{
        for (final String k in sortedPluginKeys) k: obs.plugins[k]!.toJson(),
      },
      'stability': obs.stability.toJson(),
    });
  }
}
