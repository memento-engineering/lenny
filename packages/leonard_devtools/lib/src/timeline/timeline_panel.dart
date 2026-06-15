import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/material.dart';

import 'timeline_source.dart';
import 'turn_detail_view.dart';
import 'turn_row.dart';

/// Picks a JSONL trajectory file via DTD's filesystem service and returns
/// its decoded text contents (or `null` if the user cancels).
///
/// Indirected so widget tests can pump the panel without DTD wired up.
typedef JsonlPicker = Future<String?> Function();

/// Virtualized timeline panel.
///
/// Layout: a slim header row with Live / Browse toggle buttons and an
/// expanded `ListView.builder` underneath. The list rebuilds on each new
/// record but ListView.builder + stable per-record [ValueKey]s ensure
/// existing rows are not rebuilt when the list grows (covered by the
/// "appends without rebuilding" widget test).
class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.source,
    required this.onPickJsonl,
  });

  /// The live-mode source (typically a [LiveTimelineSource] driven by the
  /// in-panel session). Used until the user toggles browse-mode.
  final TimelineSource source;

  /// Opens a JSONL trajectory file from disk via DTD and returns its
  /// content. Tests pass a stub.
  final JsonlPicker onPickJsonl;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

enum _Mode { live, browse }

class _TimelinePanelState extends State<TimelinePanel> {
  _Mode _mode = _Mode.live;
  BrowseTimelineSource? _browse;

  TimelineSource get _active => _browse ?? widget.source;

  Future<void> _enterBrowse() async {
    final jsonl = await widget.onPickJsonl();
    if (!mounted || jsonl == null) return;
    final old = _browse;
    setState(() {
      _browse = BrowseTimelineSource.fromJsonl(jsonl);
      _mode = _Mode.browse;
    });
    // Dispose the previous browse source after the swap so listeners see
    // the new value first.
    await old?.close();
  }

  Future<void> _enterLive() async {
    final old = _browse;
    setState(() {
      _browse = null;
      _mode = _Mode.live;
    });
    await old?.close();
  }

  @override
  void dispose() {
    _browse?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeBar(mode: _mode, onLive: _enterLive, onBrowse: _enterBrowse),
        const Divider(height: 1),
        Expanded(
          child: ValueListenableBuilder<List<TrajectoryRecord>>(
            valueListenable: _active.records,
            builder: (context, records, _) {
              if (records.isEmpty) {
                return Center(
                  child: Text(
                    _mode == _Mode.live
                        ? 'Waiting for trajectory records...'
                        : 'No records in selected file.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              return ListView.builder(
                key: ValueKey<_Mode>(_mode),
                itemCount: records.length,
                itemBuilder: (context, i) => _rowFor(context, records[i], i),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _rowFor(BuildContext context, TrajectoryRecord record, int i) {
    return switch (record) {
      TurnRecord t => TurnRow(
        key: ValueKey<String>('turn-${t.index}'),
        record: t,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TurnDetailView(record: t)),
        ),
      ),
      ExtensionDisabledEvent p => ExtensionDisabledRow(
        key: ValueKey<String>('disable-${p.turn}-${p.namespace}'),
        record: p,
      ),
      UnknownTrajectoryRecord u => UnknownRecordRow(
        key: ValueKey<String>('unknown-$i'),
        record: u,
      ),
      // Header/Footer don't need a row — collapse to a zero-size box so
      // the list still renders. Keys are stable on type+index.
      SessionHeader _ => SizedBox.shrink(key: ValueKey<String>('header-$i')),
      SessionFooter _ => SizedBox.shrink(key: ValueKey<String>('footer-$i')),
      _ => SizedBox.shrink(key: ValueKey<String>('skip-$i')),
    };
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.onLive,
    required this.onBrowse,
  });

  final _Mode mode;
  final VoidCallback onLive;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('Live'),
            onPressed: mode == _Mode.live ? null : onLive,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Browse JSONL'),
            onPressed: onBrowse,
          ),
        ],
      ),
    );
  }
}
