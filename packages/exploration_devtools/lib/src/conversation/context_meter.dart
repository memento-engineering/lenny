import 'package:flutter/material.dart';

import 'conversation_state.dart';

/// Renders an estimated token-usage meter as `~Nk / Mk`.
///
/// The leading tilde signals that [UsageSnapshot.estimatedTokens] is a
/// whitespace-split approximation, not the provider's real token count.
/// [UsageSnapshot.trimThreshold] is the trim-budget ceiling — the point at
/// which [ConversationBuilder.trimIfOverBudget] starts dropping old
/// observations to keep the conversation under budget. It is NOT the
/// model's maximum context window; the default ceiling is 32 000 tokens,
/// chosen to leave room for system prompt, thinking, and response.
///
/// Returns an empty widget when [usage] is null.
class ContextMeter extends StatelessWidget {
  const ContextMeter({super.key, required this.usage});

  final UsageSnapshot? usage;

  @override
  Widget build(BuildContext context) {
    final snap = usage;
    if (snap == null) return const SizedBox.shrink();
    final used = _kilo(snap.estimatedTokens);
    final ceilPart = snap.trimThreshold != null
        ? ' / ${_kilo(snap.trimThreshold!)}k'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        '~${used}k$ceilPart',
        key: const Key('contextMeter.text'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  static String _kilo(int tokens) => (tokens / 1000).round().toString();
}
