import 'package:flutter/material.dart';

import '../thinking/append_only_text_controller.dart';
import 'conversation_state.dart';

class ConversationEntryView extends StatelessWidget {
  const ConversationEntryView({
    super.key,
    required this.entry,
    this.thinkingController,
  });

  final ConversationEntry entry;
  // Non-null for the active turn (streaming); null for completed turns.
  final AppendOnlyTextController? thinkingController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Turn index label
          Text(
            'Turn ${entry.turnIndex + 1}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          // Thinking text
          if (thinkingController != null)
            _LiveThinkingText(
              key: ValueKey('thinking.${entry.turnIndex}'),
              controller: thinkingController!,
            )
          else if (thinkingController == null)
            _StaticThinkingText(
              key: ValueKey('thinking.${entry.turnIndex}.static'),
              turnIndex: entry.turnIndex,
            ),
          // Tool call chip
          if (entry.toolName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ToolCallChip(
                key: ValueKey('toolcall.${entry.turnIndex}'),
                toolName: entry.toolName!,
                args: entry.toolArgs ?? const {},
                validationOk: entry.validationOk,
              ),
            ),
          // Threaded result — indented reply style
          if (entry.complete &&
              entry.toolResult != null &&
              entry.toolResult!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, top: 2),
              child: _ToolResultCard(
                key: ValueKey('result.${entry.turnIndex}'),
                result: entry.toolResult!,
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveThinkingText extends StatelessWidget {
  const _LiveThinkingText({super.key, required this.controller});
  final AppendOnlyTextController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller,
      builder: (_, __, ___) => SelectableText(
        controller.text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

// Placeholder for completed-turn thinking. Thinking text for completed
// turns is currently not stored in ConversationState (the controller holds
// it). The AppendOnlyTextController is retained in ConversationViewModel
// for the lifetime of the ViewModel; callers should pass it via
// thinkingController even for completed turns to show the full text.
class _StaticThinkingText extends StatelessWidget {
  const _StaticThinkingText({super.key, required this.turnIndex});
  final int turnIndex;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ToolCallChip extends StatelessWidget {
  const _ToolCallChip({
    super.key,
    required this.toolName,
    required this.args,
    this.validationOk,
  });
  final String toolName;
  final Map<String, dynamic> args;
  final bool? validationOk;

  @override
  Widget build(BuildContext context) {
    final ok = validationOk;
    return Chip(
      avatar: ok == null
          ? null
          : Icon(
              ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 16,
            ),
      label: Text(
        '$toolName(${_argsSummary(args)})',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  static String _argsSummary(Map<String, dynamic> args) => args.entries
      .take(3)
      .map((kv) {
        final v = kv.value;
        return v is String ? '${kv.key}: "$v"' : '${kv.key}: $v';
      })
      .join(', ');
}

class _ToolResultCard extends StatelessWidget {
  const _ToolResultCard({super.key, required this.result});
  final String result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        result,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
