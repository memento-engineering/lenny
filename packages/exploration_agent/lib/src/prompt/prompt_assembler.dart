/// Per-turn prompt assembly (PRD §10 step 5, §16.2).
///
/// Combines the host AGENTS.md, the run goal, the running summary,
/// the last-N actions ring, the current observation, and the per-turn
/// structural diff into the [PromptPayload] shape consumed by
/// `ModelProvider`.
///
/// Crucially, the tool list passed in is forwarded to the payload
/// **unchanged**. Adding or removing a plugin from the merged set
/// changes the model's action shape on the very next turn — there is
/// no caching here (PRD §16.2). The assembler is pure: same inputs
/// always yield structurally equal payloads.
///
/// Web-compatible: pure Dart, no `dart:io`. Callers are responsible
/// for loading AGENTS.md from disk (cx6.20 CLI) and for composing the
/// merged tool list (host core + active plugin tools).
library;

import 'dart:convert';

import '../memory/action_ring.dart';
import '../memory/running_summary.dart';
import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../provider/types.dart';

/// Stateless assembler. Hold once per session; call [assemble] each turn.
class PromptAssembler {
  const PromptAssembler();

  /// Build a [PromptPayload] for a single turn.
  ///
  /// - [agentsMd], [goal], [summary.text], and each [actionRing] entry
  ///   appear verbatim in the payload's [PromptPayload.systemMessage].
  /// - [observation] and [diff] are JSON-serialised via their existing
  ///   `toJson()` shapes and placed in [PromptPayload.userMessages] as
  ///   `{type: 'text', text: ...}` entries.
  /// - [mergedTools] is forwarded to [PromptPayload.tools] unchanged
  ///   (wrapped in an unmodifiable view to discourage caller mutation).
  PromptPayload assemble({
    required String agentsMd,
    required String goal,
    required RunningSummary summary,
    required ActionRing actionRing,
    required Observation observation,
    required ObservationDiff diff,
    required List<ToolDescriptor> mergedTools,
  }) {
    final List<String> recent = actionRing.entries;
    final String actionLines = recent.isEmpty
        ? '(none yet)'
        : recent.join('\n');

    final StringBuffer sys = StringBuffer()
      ..writeln(agentsMd)
      ..writeln()
      ..writeln('## Goal')
      ..writeln(goal)
      ..writeln()
      ..writeln('## Running summary')
      ..writeln(summary.text)
      ..writeln()
      ..writeln('## Recent actions')
      ..writeln(actionLines);

    final List<Map<String, dynamic>> userMessages = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'text',
        'text': 'Observation:\n${jsonEncode(observation.toJson())}',
      },
      <String, dynamic>{
        'type': 'text',
        'text': 'Diff since last turn:\n${jsonEncode(diff.toJson())}',
      },
    ];

    return PromptPayload(
      systemMessage: sys.toString().trimRight(),
      userMessages: List<Map<String, dynamic>>.unmodifiable(userMessages),
      tools: List<ToolDescriptor>.unmodifiable(mergedTools),
    );
  }
}
