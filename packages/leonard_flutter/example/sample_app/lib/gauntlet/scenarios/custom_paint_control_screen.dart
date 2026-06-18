import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — custom-painted control with hand-authored semantics.
///
/// A segmented control (A | B | C) is drawn with [CustomPaint]. CustomPaint
/// exposes nothing on its own, so each segment is given hand-authored
/// [Semantics] (button + label + selected state) via an overlay. This tests
/// that app-authored semantics on a bespoke control flow through to the
/// agent.
///
/// Action oracle: `goal_reached` flips when segment B is selected.
class CustomPaintControlScreen extends StatefulWidget {
  const CustomPaintControlScreen({super.key});

  static const String scenarioId = 'control/custom-paint-control';
  static const List<String> segments = <String>['A', 'B', 'C'];

  @override
  State<CustomPaintControlScreen> createState() =>
      _CustomPaintControlScreenState();
}

class _CustomPaintControlScreenState extends State<CustomPaintControlScreen> {
  int _selected = 0; // default A

  void _select(int i) {
    setState(() => _selected = i);
    if (CustomPaintControlScreen.segments[i] == 'B') {
      markGoalReached(CustomPaintControlScreen.scenarioId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ScenarioHost(
      id: CustomPaintControlScreen.scenarioId,
      expected: const <String, Object?>{'target': 'B'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custom control'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Select segment B.'),
              const SizedBox(height: 20),
              SizedBox(
                width: 300,
                height: 48,
                child: Stack(
                  children: <Widget>[
                    // Visual: pixels only.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SegmentedPainter(
                          segments: CustomPaintControlScreen.segments,
                          selected: _selected,
                          active: cs.primary,
                          activeText: cs.onPrimary,
                          idleText: cs.onSurface,
                          border: cs.outline,
                        ),
                      ),
                    ),
                    // Hand-authored semantics + hit targets, one per segment.
                    Row(
                      children: <Widget>[
                        for (
                          int i = 0;
                          i < CustomPaintControlScreen.segments.length;
                          i++
                        )
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: _selected == i,
                              label:
                                  'Segment ${CustomPaintControlScreen.segments[i]}',
                              onTap: () => _select(i),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _select(i),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedPainter extends CustomPainter {
  _SegmentedPainter({
    required this.segments,
    required this.selected,
    required this.active,
    required this.activeText,
    required this.idleText,
    required this.border,
  });

  final List<String> segments;
  final int selected;
  final Color active;
  final Color activeText;
  final Color idleText;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final double w = size.width / segments.length;
    for (int i = 0; i < segments.length; i++) {
      final Rect cell = Rect.fromLTWH(w * i, 0, w, size.height);
      if (i == selected) {
        canvas.drawRect(cell, Paint()..color = active);
      }
      if (i > 0) {
        canvas.drawLine(
          Offset(w * i, 0),
          Offset(w * i, size.height),
          Paint()
            ..color = border
            ..strokeWidth = 1,
        );
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: segments[i],
          style: TextStyle(
            color: i == selected ? activeText : idleText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_SegmentedPainter old) => old.selected != selected;
}
