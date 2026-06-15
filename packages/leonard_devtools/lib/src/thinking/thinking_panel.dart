/// Thinking panel widget — renders a scrollable monospace view of the
/// model's reasoning trace, streamed live via the session's
/// `Stream<TurnEvent>`.
///
/// Web-compatible: pure Flutter, no `dart:io`.
library;

import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/material.dart';

import 'thinking_panel_controller.dart';

/// Live-streaming thinking panel.
///
/// Subscribes to the supplied [session]'s `turnEvents` stream and renders
/// the rolling reasoning trace plus per-turn `Action:` and `Validation:`
/// lines. Auto-scroll follows the bottom; manual scroll-up pauses
/// auto-scroll until the user taps the "Jump to live" affordance.
class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({super.key, required this.session});

  /// The session whose `turnEvents` drives the panel.
  final LeonardSession session;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

/// Same widget but driven by an arbitrary `Stream<TurnEvent>` — used by
/// widget tests that don't want to construct an [LeonardSession].
class ThinkingPanelFromStream extends StatefulWidget {
  const ThinkingPanelFromStream({super.key, required this.events});

  final Stream<TurnEvent> events;

  @override
  State<ThinkingPanelFromStream> createState() =>
      _ThinkingPanelFromStreamState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  late final ThinkingPanelController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = ThinkingPanelController.forSession(widget.session)..start();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ThinkingPanelView(controller: _ctl);
}

class _ThinkingPanelFromStreamState extends State<ThinkingPanelFromStream> {
  late final ThinkingPanelController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = ThinkingPanelController(widget.events)..start();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ThinkingPanelView(controller: _ctl);
}

/// Internal view shared by the two entry points. Encapsulates the
/// scrollable, the leaf [ValueListenableBuilder] that rebuilds per
/// token, and the "Jump to live" FAB.
class _ThinkingPanelView extends StatefulWidget {
  const _ThinkingPanelView({required this.controller});

  final ThinkingPanelController controller;

  @override
  State<_ThinkingPanelView> createState() => _ThinkingPanelViewState();
}

class _ThinkingPanelViewState extends State<_ThinkingPanelView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_onTextChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!widget.controller.autoScroll.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool _onScrollNotification(ScrollUpdateNotification n) {
    if (!widget.controller.autoScroll.value) return false;
    final bool atBottom =
        n.metrics.pixels >= n.metrics.maxScrollExtent - 4;
    final double delta = n.scrollDelta ?? 0;
    if (delta < 0 && !atBottom) {
      widget.controller.pauseAutoScroll();
    }
    return false;
  }

  void _onJumpToLivePressed() {
    widget.controller.resumeAutoScroll();
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScrollNotification,
            child: ValueListenableBuilder<int>(
              valueListenable: widget.controller.text,
              builder: (_, __, ___) => SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  widget.controller.text.text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.controller.autoScroll,
          builder: (_, on, __) {
            if (on) return const SizedBox.shrink();
            return Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.extended(
                key: const Key('jump-to-live'),
                onPressed: _onJumpToLivePressed,
                icon: const Icon(Icons.arrow_downward),
                label: const Text('Jump to live'),
              ),
            );
          },
        ),
      ],
    );
  }
}
