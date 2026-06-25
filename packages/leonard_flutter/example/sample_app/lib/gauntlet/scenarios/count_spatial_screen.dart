import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane C — count / spatial reasoning (hide-n-seek).
///
/// Five simple figures are drawn with [CustomPaint]; three wear a hat. The
/// count is only derivable from pixels. Classic hide-n-seek for the vision
/// model.
///
/// Answer oracle: expected.count == 3 (figures wearing a hat).
class CountSpatialScreen extends StatelessWidget {
  const CountSpatialScreen({super.key});

  static const String scenarioId = 'vision/count-spatial';

  /// One bool per figure: true == wears a hat. Three of five.
  static const List<bool> hats = <bool>[true, false, true, false, true];

  @override
  Widget build(BuildContext context) {
    final int count = hats.where((bool h) => h).length;
    return ScenarioHost(
      id: scenarioId,
      expected: <String, Object?>{'count': count},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Count'),
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
              height: 200,
              child: CustomPaint(painter: _CrowdPainter(hats)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrowdPainter extends CustomPainter {
  _CrowdPainter(this.hats);
  final List<bool> hats;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF3F1FA),
    );

    final double slot = size.width / hats.length;
    final double headR = slot * 0.18;
    final double cy = size.height * 0.5;

    for (int i = 0; i < hats.length; i++) {
      final double cx = slot * (i + 0.5);
      // Body.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, cy + headR * 2.2),
            width: headR * 2.4,
            height: headR * 3,
          ),
          Radius.circular(headR),
        ),
        Paint()..color = const Color(0xFF6E78C4),
      );
      // Head.
      canvas.drawCircle(
        Offset(cx, cy),
        headR,
        Paint()..color = const Color(0xFFF1C9A5),
      );
      // Hat (only some).
      if (hats[i]) {
        final Path hat = Path()
          ..moveTo(cx - headR * 1.2, cy - headR * 0.7)
          ..lineTo(cx + headR * 1.2, cy - headR * 0.7)
          ..lineTo(cx, cy - headR * 2.1)
          ..close();
        canvas.drawPath(hat, Paint()..color = const Color(0xFF2C2C3A));
      }
    }
  }

  @override
  bool shouldRepaint(_CrowdPainter old) => false;
}
