import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane C — OCR text baked into an image.
///
/// A price tag is rendered with [CustomPaint]/[TextPainter], so the price is
/// pixels, not a selectable/semantic `Text`. The agent must read it off the
/// screenshot.
///
/// Answer oracle: expected.price == r'$42.99'.
class OcrPriceScreen extends StatelessWidget {
  const OcrPriceScreen({super.key});

  static const String scenarioId = 'vision/ocr-price';
  static const String price = r'$42.99';
  static const String product = 'Trail Mug';

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: scenarioId,
      expected: const <String, Object?>{'price': price},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OCR price'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: ExcludeSemantics(
            child: SizedBox(
              width: 260,
              height: 180,
              child: CustomPaint(painter: _PriceTagPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceTagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final RRect card = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(card, Paint()..color = const Color(0xFFFFF6E5));
    canvas.drawRRect(
      card,
      Paint()
        ..color = const Color(0xFFE0B26A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _text(
      canvas,
      OcrPriceScreen.product,
      const Offset(20, 24),
      const TextStyle(color: Color(0xFF6B5836), fontSize: 16),
    );
    _text(
      canvas,
      OcrPriceScreen.price,
      const Offset(20, 70),
      const TextStyle(
        color: Color(0xFF1C7C2E),
        fontSize: 44,
        fontWeight: FontWeight.bold,
      ),
    );
    _text(
      canvas,
      'in stock',
      const Offset(20, 134),
      const TextStyle(color: Color(0xFF8A8170), fontSize: 13),
    );
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PriceTagPainter old) => false;
}
