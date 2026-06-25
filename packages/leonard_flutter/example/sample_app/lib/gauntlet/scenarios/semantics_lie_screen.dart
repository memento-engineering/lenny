import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane C — semantics hides a visual state.
///
/// Four status tiles. Every tile's SEMANTIC label says "status normal", but
/// one is painted red (an error). An agent that trusts the semantics tree
/// reports all-clear; only looking at pixels reveals the error tile. This is
/// the inverse of the usual trap — here the tree lies and vision is ground
/// truth.
///
/// Answer oracle: expected.error_tile == 'Tile 3' (index 2).
class SemanticsLieScreen extends StatelessWidget {
  const SemanticsLieScreen({super.key});

  static const String scenarioId = 'vision/semantics-lie';
  static const int errorIndex = 2; // zero-based -> "Tile 3"

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: scenarioId,
      expected: const <String, Object?>{
        'error_tile': 'Tile 3',
        'error_index': errorIndex,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Semantics lie'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('System status'),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  for (int i = 0; i < 4; i++) ...<Widget>[
                    Expanded(
                      child: _Tile(index: i, isError: i == errorIndex),
                    ),
                    if (i < 3) const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.index, required this.isError});

  final int index;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    // The semantic label is the SAME shape for every tile — "status normal" —
    // regardless of the painted colour. That is the lie.
    return Semantics(
      label: 'Tile ${index + 1}, status normal',
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        // Only the tile number is shown as text; the error is colour-only.
        child: ExcludeSemantics(
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
