/// Spike 4 fixture tree: root [Node] with three boxes — two live
/// (Watch-driven off StreamControllers the caller controls), one completely
/// static. Shared by the tests and the demo.
library;

import 'dart:async';

import 'package:perception/perception.dart';

import 'live_loop.dart';
import 'renderer.dart' show Field;

/// Static box that counts its builds — instrumentation for assertion (e):
/// the static box's element is mounted (and built) exactly once and never
/// rebuilt by any stream event.
class CountingStaticBox extends StatelessPerception {
  const CountingStaticBox({required this.onBuild, super.key});

  final void Function() onBuild;

  @override
  Perception build(PerceptionContext context) {
    onBuild();
    return const Node('static', children: [
      Field(name: 'mode', value: 'idle', key: 'mode'),
      Field(name: 'uptime', value: 'n/a', key: 'uptime'),
    ]);
  }
}

/// Box layout: 0 = ticker (Watch<int>), 1 = static, 2 = feed (Watch<String>).
class Spike4Fixture {
  Spike4Fixture() {
    root = Node('root', children: [
      Watch<int>(
        ticker.stream,
        (v) {
          tickerBuilds++;
          notifier.mark(0);
          return Node('ticker', children: [
            Field(name: 'count', value: '$v', key: 'count'),
            Field(name: 'square', value: '${v * v}', key: 'square'),
          ]);
        },
        initialValue: 0,
        key: 'ticker',
      ),
      CountingStaticBox(onBuild: () => staticBuilds++, key: 'static'),
      Watch<String>(
        feed.stream,
        (msg) {
          feedBuilds++;
          notifier.mark(2);
          return Node('feed', children: [
            Field(name: 'last', value: msg, key: 'last'),
          ]);
        },
        initialValue: '(none)',
        key: 'feed',
      ),
    ]);
  }

  final ticker = StreamController<int>();
  final feed = StreamController<String>();
  final notifier = RepaintNotifier();
  late final Node root;

  /// Builder/build call counters (each starts at 1 after mount).
  int tickerBuilds = 0;
  int staticBuilds = 0;
  int feedBuilds = 0;

  Future<void> dispose() async {
    await ticker.close();
    await feed.close();
  }
}
