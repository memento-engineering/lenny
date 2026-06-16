import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/api.dart';
import '../scenario_oracle.dart';

/// Lane A — debounced search.
///
/// Typing kicks off a 300ms debounce, THEN a ~600ms dio fetch, THEN the
/// results render. Three pending stages. An agent that observes right after
/// typing sees stale/empty results; it must wait through the whole chain.
///
/// Answer oracle: typing the query `widget` yields expected.count == 5.
class DebouncedSearchScreen extends ConsumerStatefulWidget {
  const DebouncedSearchScreen({super.key});

  static const String scenarioId = 'settle/debounced-search';

  @override
  ConsumerState<DebouncedSearchScreen> createState() =>
      _DebouncedSearchScreenState();
}

class _DebouncedSearchScreenState extends ConsumerState<DebouncedSearchScreen> {
  static const Duration _debounceWindow = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<String> _results = const <String>[];
  int _queryToken = 0;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, () => _run(value.trim()));
  }

  Future<void> _run(String query) async {
    final int token = ++_queryToken;
    setState(() => _searching = true);
    final List<String> results = query.isEmpty
        ? const <String>[]
        : await ref.read(apiProvider).search(query);
    // Drop stale responses (last-write-wins).
    if (!mounted || token != _queryToken) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: DebouncedSearchScreen.scenarioId,
      expected: const <String, Object?>{'query': 'widget', 'count': 5},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debounced search'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                label: 'search',
                textField: true,
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    hintText: 'Type a query',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_searching)
                const LinearProgressIndicator()
              else
                Text('${_results.length} result(s)'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    for (final String title in _results)
                      ListTile(
                        leading: const Icon(Icons.tag),
                        title: Text(title),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
