import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane C — object identification in an image.
///
/// A scene of three umbrellas is drawn with [CustomPaint]. The drawing
/// contributes NOTHING to the semantics tree, so an agent cannot find "the
/// red umbrella" by reading nodes — it must screenshot and reason over
/// pixels, then tap the right region.
///
/// Bounding-box oracle: every tap is recorded as a 0..1 fraction of the
/// scene; `goal_reached` flips when the tap lands inside the red umbrella's
/// committed fractional box (also exposed as `expected.bbox`).
class ObjectIdScreen extends StatefulWidget {
  const ObjectIdScreen({super.key});

  static const String scenarioId = 'vision/object-id';
  static const Size sceneSize = Size(320, 260);
  static const Key sceneKey = ValueKey<String>('object-id-scene');

  /// Umbrellas as (centerX, color), positioned by fraction of the scene.
  static const List<Umbrella> umbrellas = <Umbrella>[
    Umbrella(centerX: 0.24, color: Color(0xFF2E7DD7)), // blue
    Umbrella(centerX: 0.50, color: Color(0xFF2BA84A)), // green
    Umbrella(centerX: 0.78, color: Color(0xFFD7332E)), // red (target)
  ];

  /// Fractional [left, top, right, bottom] box of the red umbrella, derived
  /// from the same params used to paint it.
  static const List<double> targetBbox = <double>[
    0.78 - Umbrella.radius,
    Umbrella.canopyCy - Umbrella.radius,
    0.78 + Umbrella.radius,
    Umbrella.canopyCy + Umbrella.poleLen,
  ];

  @override
  State<ObjectIdScreen> createState() => _ObjectIdScreenState();
}

class Umbrella {
  const Umbrella({required this.centerX, required this.color});
  final double centerX;
  final Color color;

  static const double radius = 0.13; // of width
  static const double canopyCy = 0.40; // of height
  static const double poleLen = 0.30; // of height
}

class _ObjectIdScreenState extends State<ObjectIdScreen> {
  Offset? _lastTap;

  void _onTapDown(TapDownDetails d) {
    final Size s = ObjectIdScreen.sceneSize;
    final Offset f = Offset(
      (d.localPosition.dx / s.width).clamp(0.0, 1.0),
      (d.localPosition.dy / s.height).clamp(0.0, 1.0),
    );
    recordTapFraction(ObjectIdScreen.scenarioId, f);
    final List<double> b = ObjectIdScreen.targetBbox;
    final bool hit =
        f.dx >= b[0] && f.dx <= b[2] && f.dy >= b[1] && f.dy <= b[3];
    if (hit) markGoalReached(ObjectIdScreen.scenarioId);
    setState(() => _lastTap = f);
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: ObjectIdScreen.scenarioId,
      expected: const <String, Object?>{
        'target': 'red umbrella',
        'bbox': ObjectIdScreen.targetBbox,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Object ID'),
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
              // ExcludeSemantics is belt-and-suspenders: CustomPaint already
              // exposes nothing, but make the pixels-only intent explicit.
              ExcludeSemantics(
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  child: SizedBox.fromSize(
                    key: ObjectIdScreen.sceneKey,
                    size: ObjectIdScreen.sceneSize,
                    child: CustomPaint(
                      painter: _ScenePainter(marker: _lastTap),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _lastTap == null
                    ? 'Tap the red umbrella.'
                    : 'Tapped at '
                          '(${_lastTap!.dx.toStringAsFixed(2)}, '
                          '${_lastTap!.dy.toStringAsFixed(2)})',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({this.marker});
  final Offset? marker;

  @override
  void paint(Canvas canvas, Size size) {
    // Sky + ground backdrop so the scene reads as a place, not abstract.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEAF3FB),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, size.height * 0.72, size.width, size.height),
      Paint()..color = const Color(0xFFCDE8CF),
    );

    for (final Umbrella u in ObjectIdScreen.umbrellas) {
      _paintUmbrella(canvas, size, u);
    }

    if (marker != null) {
      canvas.drawCircle(
        Offset(marker!.dx * size.width, marker!.dy * size.height),
        6,
        Paint()
          ..color = const Color(0xFF111111)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _paintUmbrella(Canvas canvas, Size size, Umbrella u) {
    final double cx = u.centerX * size.width;
    final double cy = Umbrella.canopyCy * size.height;
    final double r = Umbrella.radius * size.width;
    final double poleEnd =
        (Umbrella.canopyCy + Umbrella.poleLen) * size.height;

    // Canopy: a filled semicircle.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      3.14159, // pi
      3.14159,
      true,
      Paint()..color = u.color,
    );
    // Pole.
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx, poleEnd),
      Paint()
        ..color = const Color(0xFF5A4632)
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.marker != marker;
}
