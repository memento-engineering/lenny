import 'dart:async';

import 'package:flutter/material.dart';

import 'conversation_state.dart';
import 'conversation_view_model.dart';

/// Renders the current run phase in the status header:
/// idle → running(Turn N/M · MM:SS) → done / stopped / error.
///
/// State is read exclusively from [ConversationViewModel.value]
/// ([ValueNotifier]); no raw stream subscription. A 1-second [Timer]
/// refreshes elapsed while [RunStatus.running]; cancelled on all other
/// statuses. Predictable-flutter conformant — this widget holds no
/// business logic beyond display formatting.
class RunStatusHeader extends StatefulWidget {
  const RunStatusHeader({super.key, this.vm});

  /// Null signals idle (no active session). Non-null means a session is
  /// live or has just ended.
  final ConversationViewModel? vm;

  @override
  State<RunStatusHeader> createState() => _RunStatusHeaderState();
}

class _RunStatusHeaderState extends State<RunStatusHeader> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.vm?.addListener(_onStateChanged);
    _syncTicker(widget.vm?.value);
  }

  @override
  void didUpdateWidget(covariant RunStatusHeader old) {
    super.didUpdateWidget(old);
    if (old.vm != widget.vm) {
      old.vm?.removeListener(_onStateChanged);
      widget.vm?.addListener(_onStateChanged);
      _elapsed = Duration.zero;
      _syncTicker(widget.vm?.value);
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.vm?.removeListener(_onStateChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onStateChanged() {
    _syncTicker(widget.vm?.value);
    setState(() {});
  }

  void _syncTicker(ConversationState? state) {
    if (state?.status == RunStatus.running) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        final startedAt = widget.vm?.value.startedAt;
        if (startedAt != null && mounted) {
          setState(() => _elapsed = DateTime.now().difference(startedAt));
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    if (vm == null) {
      return const _StatusChip(key: Key('runStatus.idle'), label: 'idle');
    }
    return switch (vm.value.status) {
      RunStatus.idle =>
        const _StatusChip(key: Key('runStatus.idle'), label: 'idle'),
      RunStatus.running =>
        _StatusChip(
          key: const Key('runStatus.running'),
          label: _runningLabel(vm.value),
        ),
      RunStatus.done =>
        const _StatusChip(key: Key('runStatus.done'), label: 'done'),
      RunStatus.stopped =>
        const _StatusChip(key: Key('runStatus.stopped'), label: 'stopped'),
      RunStatus.error =>
        const _StatusChip(key: Key('runStatus.error'), label: 'error'),
    };
  }

  String _runningLabel(ConversationState state) {
    final turn = state.currentTurn >= 0 ? state.currentTurn + 1 : 1;
    final maxPart = state.maxTurns != null ? '/${state.maxTurns}' : '';
    final mm = _elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return 'Turn $turn$maxPart · $mm:$ss';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}
