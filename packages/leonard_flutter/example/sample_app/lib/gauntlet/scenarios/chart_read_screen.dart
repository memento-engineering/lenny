import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane C — read an infographic.
///
/// A bar chart is drawn entirely with [CustomPaint] (bars + axis + painted
/// labels). None of the values or quarter labels are in the semantics tree,
/// so "which quarter had the highest revenue?" can only be answered from
/// pixels.
///
/// Answer oracle: expected.answer == 'Q3' (the tallest bar).
class ChartReadScreen extends StatelessWidget {
  const ChartReadScreen({super.key});

  static const String scenarioId = 'vision/chart-read';

  /// (label, value). Q3 is the tallest — the committed answer.
  static const List<(String, double)> bars = <(String, double)>[
    ('Q1', 40),
    ('Q2', 65),
    ('Q3', 90),
    ('Q4', 55),
  ];

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: scenarioId,
      expected: const <String, Object?>{'answer': 'Q3'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chart read'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: ExcludeSemantics(
            child: SizedBox(
              width: 320,
              height: 240,
              child: CustomPaint(painter: _BarChartPainter(bars)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter(this.bars);
  final List<(String, double)> bars;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    const double padL = 28, padB = 28, padT = 16, padR = 12;
    final Rect plot = Rect.fromLTRB(
      padL,
      padT,
      size.width - padR,
      size.height - padB,
    );

    // Axes.
    final Paint axis = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axis);

    final double maxV = bars.map((b) => b.$2).reduce((a, b) => a > b ? a : b);
    final double slot = plot.width / bars.length;
    const double barFrac = 0.55;

    for (int i = 0; i < bars.length; i++) {
      final (String label, double value) = bars[i];
      final double h = plot.height * (value / maxV);
      final double bw = slot * barFrac;
      final double left = plot.left + slot * i + (slot - bw) / 2;
      final Rect bar = Rect.fromLTWH(left, plot.bottom - h, bw, h);
      canvas.drawRect(bar, Paint()..color = const Color(0xFF3F6FD8));

      // Painted value above the bar + quarter label below the axis.
      _label(canvas, value.toInt().toString(), bar.center.dx, bar.top - 12);
      _label(canvas, label, bar.center.dx, plot.bottom + 6, top: true);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    double cx,
    double y, {
    bool top = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF222222), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, top ? y : y));
  }

  @override
  bool shouldRepaint(_BarChartPainter old) => false;
}
