import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:exploration_flutter/exploration_flutter.dart';

void main() {
  late ExplorationBinding binding;

  setUpAll(() {
    binding = ExplorationBinding.ensureInitialized(
      plugins: const [],
      errorBufferCapacity: 3,
    )!;
    expect(binding.debugErrorBufferCapacity(), 3);
  });

  test('get_recent_errors with empty buffer returns empty entries + cursor=0',
      () async {
    final String json = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{},
    );
    final Map<String, Object?> decoded =
        jsonDecode(json) as Map<String, Object?>;
    expect(decoded['entries'], isEmpty);
    expect(decoded['cursor'], 0);
  });

  test('get_recent_errors returns the suffix newer than `since`', () async {
    binding.debugAppendError('a', null);
    binding.debugAppendError('b', null);
    binding.debugAppendError('c', null);
    expect(binding.debugHighestErrorSeq(), 3);

    // Without `since` -> all 3 entries, cursor=3.
    String raw = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{},
    );
    Map<String, Object?> decoded = jsonDecode(raw) as Map<String, Object?>;
    List<dynamic> entries = decoded['entries']! as List<dynamic>;
    expect(entries.length, 3);
    expect(decoded['cursor'], 3);

    // With since=2 -> only seq 3.
    raw = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{'since': '2'},
    );
    decoded = jsonDecode(raw) as Map<String, Object?>;
    entries = decoded['entries']! as List<dynamic>;
    expect(entries.length, 1);
    expect((entries.first as Map<String, dynamic>)['seq'], 3);
    expect(decoded['cursor'], 3);

    // With since=3 -> empty, cursor=3 (highestSeq).
    raw = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{'since': '3'},
    );
    decoded = jsonDecode(raw) as Map<String, Object?>;
    expect(decoded['entries'], isEmpty);
    expect(decoded['cursor'], 3,
        reason: 'cursor returns the input `since` value when no entries '
            'are newer (so the harness never goes backwards)');
  });

  test('get_recent_errors evicts oldest when capacity exceeded', () async {
    // Buffer is capacity=3, currently holds seq 1..3. Add a 4th -> evict 1.
    binding.debugAppendError('d', null);
    expect(binding.debugHighestErrorSeq(), 4);

    final String raw = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{'since': '0'},
    );
    final Map<String, Object?> decoded =
        jsonDecode(raw) as Map<String, Object?>;
    final List<dynamic> entries = decoded['entries']! as List<dynamic>;
    expect(entries.length, 3);
    expect((entries.first as Map<String, dynamic>)['seq'], 2,
        reason: 'after eviction, the oldest retained seq is 2');
    expect((entries.last as Map<String, dynamic>)['seq'], 4);
    expect(decoded['cursor'], 4);
  });

  test('get_recent_errors entry shape', () async {
    final String raw = await binding.invokeServiceExtension(
      'ext.exploration.core.get_recent_errors',
      <String, String>{'since': '3'},
    );
    final Map<String, Object?> decoded =
        jsonDecode(raw) as Map<String, Object?>;
    final List<dynamic> entries = decoded['entries']! as List<dynamic>;
    final Map<String, dynamic> entry =
        entries.single as Map<String, dynamic>;
    expect(entry.keys.toSet(),
        <String>{'seq', 'message', 'frames', 'wallClockOffsetMs'});
    expect(entry['seq'], 4);
    expect(entry['message'], 'd');
    expect(entry['frames'], isA<List<dynamic>>());
    expect(entry['wallClockOffsetMs'], isA<int>());
  });

  test('extension is registered with the local binding', () {
    expect(
      binding.debugHasRegisteredExtension(
          'ext.exploration.core.get_recent_errors'),
      isTrue,
    );
  });
}
