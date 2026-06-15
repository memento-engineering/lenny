import 'dart:async';

import 'package:leonard_agent/src/provider/frontier/thinking_decoder.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

void main() {
  test(
    'emits thinking_delta text then isFinal on content_block_stop',
    () async {
      final ctrl = StreamController<ThinkingDelta>.broadcast();
      final d = ThinkingSseDecoder(ctrl);
      final got = <ThinkingDelta>[];
      final sub = ctrl.stream.listen(got.add);
      d.onEvent(<String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{'type': 'thinking', 'thinking': ''},
      });
      d.onEvent(<String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'thinking_delta',
          'thinking': 'Here',
        },
      });
      d.onEvent(<String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{'type': 'thinking_delta', 'thinking': "'s"},
      });
      d.onEvent(<String, dynamic>{'type': 'content_block_stop', 'index': 0});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got.map((e) => e.text).toList(), <String>['Here', "'s", '']);
      expect(got.last.isFinal, isTrue);
    },
  );

  test('ignores non-thinking content_block_stop', () async {
    final ctrl = StreamController<ThinkingDelta>.broadcast();
    final d = ThinkingSseDecoder(ctrl);
    final got = <ThinkingDelta>[];
    final sub = ctrl.stream.listen(got.add);
    d.onEvent(<String, dynamic>{
      'type': 'content_block_start',
      'index': 1,
      'content_block': <String, dynamic>{'type': 'tool_use'},
    });
    d.onEvent(<String, dynamic>{'type': 'content_block_stop', 'index': 1});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got, isEmpty);
  });

  test('onDone flushes a still-open thinking block as final', () async {
    final ctrl = StreamController<ThinkingDelta>.broadcast();
    final d = ThinkingSseDecoder(ctrl);
    final got = <ThinkingDelta>[];
    final sub = ctrl.stream.listen(got.add);
    d.onEvent(<String, dynamic>{
      'type': 'content_block_start',
      'index': 0,
      'content_block': <String, dynamic>{'type': 'thinking'},
    });
    d.onEvent(<String, dynamic>{
      'type': 'content_block_delta',
      'index': 0,
      'delta': <String, dynamic>{'type': 'thinking_delta', 'thinking': 'x'},
    });
    d.onDone();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got.map((e) => e.text).toList(), <String>['x', '']);
    expect(got.last.isFinal, isTrue);
  });
}
