import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/material.dart';

import '../timeline/timeline_panel.dart';
import '../timeline/timeline_source.dart';

/// Mounts the Timeline tab in [LeonardShell].
///
/// Owns a [LiveTimelineSource] backed by an empty broadcast stream until
/// the in-panel session loop publishes its live trajectory stream.
///
/// The browse-mode JSONL picker is currently a paste-area dialog that
/// accepts the JSONL content directly. A real DTD file picker (using
/// `dtd.readFileAsString` against a user-chosen URI) is tracked as a
/// follow-up; this seam is the typedef [JsonlPicker], so swapping in a
/// real picker is a one-liner in [build].
class TimelinePanelMount extends StatefulWidget {
  const TimelinePanelMount({
    super.key,
    this.trajectoryStream,
    this.jsonlPicker,
  });

  /// Optional override for the live trajectory stream — tests pass a
  /// controllable stream. Production uses an empty broadcast stream
  /// until the session loop is wired up.
  final Stream<TrajectoryRecord>? trajectoryStream;

  /// Optional override for the browse picker. Tests / future
  /// integrations swap in a real DTD-backed picker here.
  final JsonlPicker? jsonlPicker;

  @override
  State<TimelinePanelMount> createState() => _TimelinePanelMountState();
}

class _TimelinePanelMountState extends State<TimelinePanelMount> {
  StreamController<TrajectoryRecord>? _ownedController;
  late LiveTimelineSource _liveSource;

  void _bind(Stream<TrajectoryRecord>? provided) {
    if (provided != null) {
      _ownedController = null;
      _liveSource = LiveTimelineSource(provided);
    } else {
      _ownedController = StreamController<TrajectoryRecord>.broadcast();
      _liveSource = LiveTimelineSource(_ownedController!.stream);
    }
  }

  @override
  void initState() {
    super.initState();
    _bind(widget.trajectoryStream);
  }

  @override
  void didUpdateWidget(covariant TimelinePanelMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.trajectoryStream, widget.trajectoryStream)) return;
    final LiveTimelineSource previousSource = _liveSource;
    final StreamController<TrajectoryRecord>? previousController =
        _ownedController;
    _bind(widget.trajectoryStream);
    unawaited(previousSource.close());
    unawaited(previousController?.close());
  }

  @override
  void dispose() {
    _liveSource.close();
    _ownedController?.close();
    super.dispose();
  }

  Future<String?> _defaultPicker() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Open trajectory JSONL'),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Paste JSONL contents',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Load'),
            ),
          ],
        );
      },
    );
    if (result == null || result.trim().isEmpty) return null;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return TimelinePanel(
      source: _liveSource,
      onPickJsonl: widget.jsonlPicker ?? _defaultPicker,
    );
  }
}
