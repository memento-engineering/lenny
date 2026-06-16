import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/api.dart';
import '../scenario_oracle.dart';

/// Lane A — optimistic-then-reconcile.
///
/// Tapping "Like" fills the heart instantly (optimistic), but the server
/// reconciles it back to NOT liked ~800ms later. An agent that observes
/// during the optimistic window reports the wrong (liked) state; a
/// settle-aware agent waits out the in-flight `dio` reconcile and reports
/// the settled state.
///
/// Answer oracle: expected.settled_liked == false.
class OptimisticRevertScreen extends ConsumerStatefulWidget {
  const OptimisticRevertScreen({super.key});

  static const String scenarioId = 'settle/optimistic-revert';

  @override
  ConsumerState<OptimisticRevertScreen> createState() =>
      _OptimisticRevertScreenState();
}

class _OptimisticRevertScreenState
    extends ConsumerState<OptimisticRevertScreen> {
  bool _liked = false;
  bool _pending = false;

  Future<void> _toggle() async {
    // Optimistic flash: show liked immediately.
    setState(() {
      _liked = true;
      _pending = true;
    });
    final bool settled = await ref.read(apiProvider).toggleLike();
    if (!mounted) return;
    // Reconcile to the server's truth (always false here).
    setState(() {
      _liked = settled;
      _pending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: OptimisticRevertScreen.scenarioId,
      expected: const <String, Object?>{'settled_liked': false},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Optimistic revert'),
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
              IconButton(
                iconSize: 64,
                tooltip: _liked ? 'Liked' : 'Not liked',
                icon: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? Colors.red : null,
                ),
                onPressed: _pending ? null : _toggle,
              ),
              const SizedBox(height: 8),
              Text('Liked: ${_liked ? 'yes' : 'no'}'),
              if (_pending) ...<Widget>[
                const SizedBox(height: 16),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
