/// Unit tests for [DogfoodTraceWriter] (bead lenny-cx6.43, step 4).
library;

import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart' show TrajectorySink;
import 'package:exploration_agent/src/dogfood/trace_writer.dart';
import 'package:exploration_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:test/test.dart';

class _MemorySink implements TrajectorySink {
  final List<String> lines = <String>[];
  bool flushed = false;
  bool closed = false;

  @override
  Future<void> writeLine(String l) async => lines.add(l);

  @override
  Future<void> flush() async {
    flushed = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

const ToolDescriptor _tap = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node',
  inputSchema: <String, dynamic>{'type': 'object'},
);

void main() {
  group('DogfoodTraceWriter', () {
    test('writes header + N turn + footer JSONL lines in order', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '/tmp/test.jsonl');

      await writer.writeHeader(
        goal: 'turn on dark mode',
        model: 'qwen3.6-27b',
        tools: <ToolDescriptor>[_tap],
      );
      await writer.writeTurn(
        index: 0,
        prompt: 'p0',
        decision: <String, dynamic>{'tool': 'core.tap'},
        actResult: <String, dynamic>{'ok': true},
        elapsedMs: 123,
      );
      await writer.writeTurn(
        index: 1,
        prompt: 'p1',
        decision: null,
        actResult: null,
        elapsedMs: 0,
        error: 'turn_timeout',
      );
      await writer.writeFooter(outcome: 'completedWithToolCall');

      expect(sink.lines.length, 4);

      final h = jsonDecode(sink.lines[0]) as Map<String, dynamic>;
      expect(h['type'], 'dogfood_header');
      expect(h['goal'], 'turn on dark mode');
      expect(h['model'], 'qwen3.6-27b');
      expect((h['tools'] as List).single['name'], 'core.tap');
      expect(h['started_at'], isA<String>());

      final t0 = jsonDecode(sink.lines[1]) as Map<String, dynamic>;
      expect(t0['type'], 'dogfood_turn');
      expect(t0['index'], 0);
      expect(t0['prompt'], 'p0');
      expect((t0['decision'] as Map)['tool'], 'core.tap');
      expect(t0['elapsed_ms'], 123);
      expect(t0.containsKey('error'), isFalse);

      final t1 = jsonDecode(sink.lines[2]) as Map<String, dynamic>;
      expect(t1['type'], 'dogfood_turn');
      expect(t1['index'], 1);
      expect(t1['decision'], isNull);
      expect(t1['error'], 'turn_timeout');

      final f = jsonDecode(sink.lines[3]) as Map<String, dynamic>;
      expect(f['type'], 'dogfood_footer');
      expect(f['outcome'], 'completedWithToolCall');
      expect(f.containsKey('exception'), isFalse);

      expect(sink.closed, isTrue);
      expect(sink.flushed, isTrue);
    });

    test('footer carries exception string when supplied', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '<memory>');
      await writer.writeHeader(
        goal: 'g',
        model: 'm',
        tools: const <ToolDescriptor>[],
      );
      await writer.writeFooter(
        outcome: 'typedException',
        exception: 'SchemaRejection: nope',
      );
      final f = jsonDecode(sink.lines.last) as Map<String, dynamic>;
      expect(f['outcome'], 'typedException');
      expect(f['exception'], 'SchemaRejection: nope');
    });

    test('writeTurn before writeHeader throws', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '<memory>');
      await expectLater(
        writer.writeTurn(
          index: 0,
          prompt: '',
          decision: null,
          actResult: null,
          elapsedMs: 0,
        ),
        throwsStateError,
      );
    });

    test('double-header rejected', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '<memory>');
      await writer.writeHeader(
        goal: 'g',
        model: 'm',
        tools: const <ToolDescriptor>[],
      );
      await expectLater(
        writer.writeHeader(
          goal: 'g',
          model: 'm',
          tools: const <ToolDescriptor>[],
        ),
        throwsStateError,
      );
    });

    test('writeFooter is idempotent', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '<memory>');
      await writer.writeHeader(
        goal: 'g',
        model: 'm',
        tools: const <ToolDescriptor>[],
      );
      await writer.writeFooter(outcome: 'completedNoToolCall');
      final lengthAfterFirst = sink.lines.length;
      await writer.writeFooter(outcome: 'completedNoToolCall');
      expect(sink.lines.length, lengthAfterFirst);
    });

    test('writeFooter without header synthesizes a header', () async {
      final sink = _MemorySink();
      final writer = DogfoodTraceWriter(sink, '<memory>');
      await writer.writeFooter(outcome: 'budgetExceeded');
      expect(sink.lines.length, 2);
      final h = jsonDecode(sink.lines[0]) as Map<String, dynamic>;
      expect(h['type'], 'dogfood_header');
      expect(h['synthetic'], isTrue);
      final f = jsonDecode(sink.lines[1]) as Map<String, dynamic>;
      expect(f['type'], 'dogfood_footer');
      expect(f['outcome'], 'budgetExceeded');
    });
  });
}
