import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/api.dart';
import '../scenario_oracle.dart';

/// Lane A — async-gated reveal.
///
/// A confirmation code exists only AFTER a ~1.5s dio round-trip. An agent
/// that observes too early sees a spinner and no code. The right behaviour
/// is to notice the in-flight `dio` work (reported in the observation's
/// stability block) and re-observe until it settles, then read the code.
///
/// Answer oracle: expected.code — the grader compares the agent's reported
/// code against it. The code IS in the semantics tree once loaded; the trap
/// is purely timing.
class AsyncRevealScreen extends ConsumerStatefulWidget {
  const AsyncRevealScreen({super.key});

  static const String scenarioId = 'settle/async-reveal';

  @override
  ConsumerState<AsyncRevealScreen> createState() => _AsyncRevealScreenState();
}

class _AsyncRevealScreenState extends ConsumerState<AsyncRevealScreen> {
  late final Future<String> _code = ref
      .read(apiProvider)
      .fetchConfirmationCode();

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: AsyncRevealScreen.scenarioId,
      expected: const <String, Object?>{'code': 'AZ-4471'},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Async reveal'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Center(
          child: FutureBuilder<String>(
            future: _code,
            builder: (BuildContext context, AsyncSnapshot<String> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Fetching confirmation…'),
                  ],
                );
              }
              if (snap.hasError) {
                return Text('Error: ${snap.error}');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Your confirmation code is'),
                  const SizedBox(height: 8),
                  Text(
                    snap.data!,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
