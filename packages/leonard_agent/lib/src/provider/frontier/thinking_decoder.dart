import 'dart:async';

import '../types.dart';

/// Decodes Anthropic-native thinking from an SSE event stream into
/// [ThinkingDelta]s on the provided sink. Caller drives by invoking
/// [onEvent] for each decoded SSE JSON event and [onDone] when the
/// stream terminates.
///
/// Wire shape (per swift-infer + Anthropic /v1/messages):
///   content_block_start { content_block: {type: "thinking"}, index: N }
///   content_block_delta { delta: {type: "thinking_delta", thinking: "…"}, index: N }
///   content_block_stop  { index: N }
///
/// On each `thinking_delta` we emit `ThinkingDelta(text, isFinal:false)`.
/// On the `content_block_stop` whose index matches an open thinking
/// block we emit `ThinkingDelta(text:'', isFinal:true)` and forget the
/// index. Unknown / non-thinking events are ignored.
class ThinkingSseDecoder {
  ThinkingSseDecoder(this._sink);

  final StreamController<ThinkingDelta> _sink;
  final Set<int> _openThinkingBlocks = <int>{};

  /// Feed one parsed SSE event JSON map.
  void onEvent(Map<String, dynamic> evt) {
    final type = evt['type'] as String?;
    final index = evt['index'] as int?;
    if (type == 'content_block_start') {
      final block = (evt['content_block'] as Map?)?.cast<String, dynamic>();
      if (block != null && block['type'] == 'thinking' && index != null) {
        _openThinkingBlocks.add(index);
      }
    } else if (type == 'content_block_delta') {
      final delta = (evt['delta'] as Map?)?.cast<String, dynamic>();
      if (delta == null) return;
      if (delta['type'] == 'thinking_delta') {
        final t = delta['thinking'] as String? ?? '';
        if (t.isNotEmpty) {
          _sink.add(ThinkingDelta(text: t, isFinal: false));
        }
      }
    } else if (type == 'content_block_stop') {
      if (index != null && _openThinkingBlocks.remove(index)) {
        _sink.add(const ThinkingDelta(text: '', isFinal: true));
      }
    }
  }

  /// Flush any still-open thinking blocks as final. Defensive — Anthropic
  /// always sends content_block_stop, but a truncated stream shouldn't
  /// leave the panel hanging without an `isFinal` marker.
  void onDone() {
    if (_openThinkingBlocks.isNotEmpty) {
      _sink.add(const ThinkingDelta(text: '', isFinal: true));
      _openThinkingBlocks.clear();
    }
  }
}
