import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/material.dart';

/// Three-line summary row for a [TurnRecord].
///
/// Line 1: tool name + first three args, single-line ellipsised.
/// Line 2: diff summary derived from `diff.core` (nodes added/removed,
///         route change) and any extension-namespaced diff fragments.
/// Line 3: thinking trace truncated for the row (full text shown in
///         the turn detail view).
class TurnRow extends StatelessWidget {
  const TurnRow({super.key, required this.record, required this.onTap});

  final TurnRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLine = describeAction(
      record.executedAction,
      index: record.index,
    );
    final diffLine = describeDiff(record.diff);
    final thinking = record.thinking;
    final summary = (thinking == null || thinking.isEmpty)
        ? '(no thinking)'
        : thinking.length > 80
        ? '${thinking.substring(0, 80)}…'
        : thinking;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              actionLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              diffLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the `#<idx> tool(arg=value, ...)` string for line 1.
  static String describeAction(
    Map<String, dynamic> action, {
    required int index,
  }) {
    final tool = action['tool'] as String? ?? '<unknown>';
    final args = action['args'];
    final argsLabel = args is Map
        ? args.entries.take(3).map((e) => '${e.key}=${e.value}').join(', ')
        : '';
    return '#$index $tool($argsLabel)';
  }

  /// Builds the diff one-liner. Reads `diff.core` for node/route deltas
  /// and surfaces any extension-namespaced fragments in `diff.plugins`.
  static String describeDiff(Map<String, dynamic> diff) {
    final parts = <String>[];

    final core = diff['core'];
    if (core is Map) {
      final added = core['nodes_added'];
      if (added is List && added.isNotEmpty) {
        parts.add('+${added.length} nodes');
      }
      final removed = core['nodes_removed'];
      if (removed is List && removed.isNotEmpty) {
        parts.add('-${removed.length} nodes');
      }
      final routeChanges = core['route_changes'];
      if (routeChanges is List && routeChanges.isNotEmpty) {
        final last = routeChanges.last;
        if (last is Map) {
          final current = last['current'];
          if (current is List) {
            parts.add('route -> ${current.join('/')}');
          }
        }
      }
    }

    final plugins = diff['extensions'];
    if (plugins is Map) {
      for (final entry in plugins.entries) {
        parts.add('${entry.key}: changed');
      }
    }

    return parts.isEmpty ? '(no changes)' : parts.join(', ');
  }
}

/// Distinct row variant for a `extension_disabled` event. Surfaces the
/// affected namespace and reason between turn rows.
class ExtensionDisabledRow extends StatelessWidget {
  const ExtensionDisabledRow({super.key, required this.record});

  final ExtensionDisabledEvent record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        'extension disabled (turn ${record.turn}): ${record.namespace} — ${record.reason}',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

/// Row variant for unknown record types. AC requires schema-mismatch
/// rendering as a non-fatal warning row.
class UnknownRecordRow extends StatelessWidget {
  const UnknownRecordRow({super.key, required this.record});

  final UnknownTrajectoryRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        'unknown record type: ${record.rawType}',
        style: TextStyle(color: scheme.error, fontStyle: FontStyle.italic),
      ),
    );
  }
}
