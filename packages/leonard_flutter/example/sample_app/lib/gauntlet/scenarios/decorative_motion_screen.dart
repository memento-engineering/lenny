import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane A — the settle policy's falsifier.
///
/// The screen runs a shimmer + a pulsing icon on a perpetual
/// `AnimationController.repeat()`. These animate PIXELS ONLY (opacity and a
/// sliding gradient): no layout changes, no semantics changes, no route
/// changes. So from the binding's point of view a transient frame callback
/// is *always* scheduled (the ticker reschedules every tick), which means
/// `FrameworkBusySnapshot.isAnyBusy` is true on every poll and the stable
/// observation loop can never reach `idle`/`quiet_frame`.
///
/// Expected behaviour to observe (this is the experiment):
///   * `action-relative` → terminates `budget` after the full budget every
///     turn, since neither route nor semantics hash changes.
///   * `idle` / `frame-stable` → terminate via the defensive `kMaxBudgetMs`
///     guard, also `budget`.
///   * `framework_busy.transient_callbacks` is > 0 in the stability block —
///     the direct evidence of the cause.
///
/// The screen is still fully actionable: the "I'm ready" button is a normal
/// semantics node. The agent's goal is to tap it; doing so flips the
/// oracle's `goal_reached`. The point of the scenario is that the agent can
/// only act if the settle loop *returns an observation at all* despite the
/// perpetual motion — and to surface how badly the motion degrades settle
/// latency.
class DecorativeMotionScreen extends StatefulWidget {
  const DecorativeMotionScreen({super.key});

  static const String scenarioId = 'settle/decorative-motion';

  @override
  State<DecorativeMotionScreen> createState() => _DecorativeMotionScreenState();
}

class _DecorativeMotionScreenState extends State<DecorativeMotionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  bool _confirmed = false;

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: DecorativeMotionScreen.scenarioId,
      expected: const <String, Object?>{'action': 'tap_ready'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Decorative motion'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Decorative, perpetual, pixel-only. Excluded from
                  // semantics so it adds no nodes — it exists purely to keep
                  // the framework "busy".
                  ExcludeSemantics(
                    child: Column(
                      children: <Widget>[
                        _Pulse(
                          animation: _pulse,
                          child: const Icon(Icons.sync, size: 48),
                        ),
                        const SizedBox(height: 20),
                        for (int i = 0; i < 3; i++) ...<Widget>[
                          _ShimmerBar(animation: _shimmer),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _confirmed
                        ? 'Confirmed — page is ready.'
                        : 'The page has finished loading. '
                              'Confirm when you can see it.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: Icon(_confirmed ? Icons.check : Icons.done_all),
                    label: Text(_confirmed ? 'Ready ✓' : "I'm ready"),
                    onPressed: _confirmed
                        ? null
                        : () {
                            markGoalReached(DecorativeMotionScreen.scenarioId);
                            setState(() => _confirmed = true);
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opacity+scale pulse driven by a perpetual controller. Pixel-only.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double t = animation.value;
        return Opacity(
          opacity: 0.4 + 0.6 * t,
          child: Transform.scale(scale: 0.9 + 0.2 * t, child: child),
        );
      },
      child: child,
    );
  }
}

/// Skeleton "loading" bar with a gradient highlight sweeping across it on a
/// perpetual controller. Pixel-only — its geometry never changes.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Color highlight = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = animation.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) {
            final double dx = bounds.width * (2 * t - 0.5);
            return LinearGradient(
              colors: <Color>[base, highlight, base],
              stops: const <double>[0.35, 0.5, 0.65],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      },
    );
  }
}

/// Translates a gradient horizontally by [dx] logical px.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}
