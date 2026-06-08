import 'package:flutter/material.dart';

import 'conversation_entry_view.dart';
import 'conversation_view_model.dart';

class TranscriptList extends StatefulWidget {
  const TranscriptList({super.key, required this.viewModel});
  final ConversationViewModel viewModel;

  @override
  State<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<TranscriptList> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant TranscriptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onStateChanged);
      widget.viewModel.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onStateChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  bool _onScrollNotification(ScrollUpdateNotification n) {
    final delta = n.scrollDelta ?? 0;
    final atBottom = n.metrics.pixels >= n.metrics.maxScrollExtent - 4;
    if (delta < 0 && !atBottom && _autoScroll) {
      setState(() => _autoScroll = false);
    }
    return false;
  }

  void _jumpToLive() {
    setState(() => _autoScroll = true);
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScrollNotification,
          child: ValueListenableBuilder(
            valueListenable: widget.viewModel,
            builder: (context, state, _) {
              final entries = state.entries;
              if (entries.isEmpty) {
                return const Center(
                  child: Text(
                    'Waiting for the first turn…',
                    key: Key('transcript.empty'),
                  ),
                );
              }
              return ListView.separated(
                key: const Key('transcript.list'),
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return ConversationEntryView(
                    key: ValueKey('entry.${entry.turnIndex}'),
                    entry: entry,
                    thinkingController: widget.viewModel
                        .thinkingControllerForTurn(entry.turnIndex),
                  );
                },
              );
            },
          ),
        ),
        if (!_autoScroll)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.extended(
              key: const Key('transcript.jumpToLive'),
              onPressed: _jumpToLive,
              icon: const Icon(Icons.arrow_downward),
              label: const Text('Jump to live'),
            ),
          ),
      ],
    );
  }
}
