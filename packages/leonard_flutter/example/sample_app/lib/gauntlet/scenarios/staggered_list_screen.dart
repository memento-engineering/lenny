import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane A — staggered list entrance.
///
/// Twenty items are added to the list one at a time over ~1s, each fading
/// in. Because items enter the SEMANTICS tree incrementally, an agent that
/// counts too early gets fewer than 20. The settle signal here is
/// semantics-change: the agent must keep re-observing until the tree stops
/// changing, then count.
///
/// Answer oracle: expected.count == 20 (the final, settled count).
class StaggeredListScreen extends StatefulWidget {
  const StaggeredListScreen({super.key});

  static const String scenarioId = 'settle/staggered-list';
  static const int total = 20;

  @override
  State<StaggeredListScreen> createState() => _StaggeredListScreenState();
}

class _StaggeredListScreenState extends State<StaggeredListScreen> {
  int _visible = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (Timer t) {
      if (_visible >= StaggeredListScreen.total) {
        t.cancel();
        return;
      }
      setState(() => _visible++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: StaggeredListScreen.scenarioId,
      expected: const <String, Object?>{'count': StaggeredListScreen.total},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staggered list'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: ListView.builder(
          itemCount: _visible,
          itemBuilder: (BuildContext context, int i) {
            return TweenAnimationBuilder<double>(
              key: ValueKey<int>(i),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (BuildContext context, double t, Widget? child) {
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text('Row ${i + 1}'),
              ),
            );
          },
        ),
      ),
    );
  }
}
