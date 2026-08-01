import 'package:flutter/material.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

import 'diagnostics_snapshot.dart';
import 'tree_snapshot_view.dart';

sealed class DiagnosticsPanelState {
  const DiagnosticsPanelState();
}

final class DiagnosticsLoading extends DiagnosticsPanelState {
  const DiagnosticsLoading();
}

final class DiagnosticsLoaded extends DiagnosticsPanelState {
  const DiagnosticsLoaded(this.snapshot);
  final TreeSnapshot snapshot;
}

final class DiagnosticsFailed extends DiagnosticsPanelState {
  const DiagnosticsFailed(this.message);
  final String message;
}

/// Owns initial load, refresh, and stale-result suppression.
final class DiagnosticsPanelController
    extends ValueNotifier<DiagnosticsPanelState> {
  DiagnosticsPanelController({required DiagnosticsSnapshotLoader loader})
    : _loader = loader,
      super(const DiagnosticsLoading());
  final DiagnosticsSnapshotLoader _loader;
  int _generation = 0;
  Future<void> refresh() async {
    final int generation = ++_generation;
    value = const DiagnosticsLoading();
    try {
      final TreeSnapshot snapshot = await _loader();
      if (generation == _generation) value = DiagnosticsLoaded(snapshot);
    } catch (error) {
      if (generation == _generation) value = DiagnosticsFailed('$error');
    }
  }
}

/// Refreshable diagnostics inspector panel.
class DiagnosticsPanel extends StatefulWidget {
  const DiagnosticsPanel({super.key, required this.loader, this.controller});
  final DiagnosticsSnapshotLoader loader;
  final DiagnosticsPanelController? controller;
  @override
  State<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  late final DiagnosticsPanelController _controller =
      widget.controller ?? DiagnosticsPanelController(loader: widget.loader);
  bool get _ownsController => widget.controller == null;
  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          key: const Key('diagnostics.refresh'),
          onPressed: _controller.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      Expanded(
        child: ValueListenableBuilder<DiagnosticsPanelState>(
          valueListenable: _controller,
          builder: (_, DiagnosticsPanelState state, __) => switch (state) {
            DiagnosticsLoading() => const Center(
              key: Key('diagnostics.loading'),
              child: CircularProgressIndicator(),
            ),
            DiagnosticsLoaded(:final snapshot) => TreeSnapshotView(
              key: const Key('diagnostics.tree'),
              snapshot: snapshot,
            ),
            DiagnosticsFailed(:final message) => Center(
              key: const Key('diagnostics.error'),
              child: Text(message),
            ),
          },
        ),
      ),
    ],
  );
}
