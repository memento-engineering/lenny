// lenny#178: every model call is counted — retries and failures included —
// into each turn's model_metadata.usage and the footer's run totals.
import 'dart:convert';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

class _MemorySink extends TrajectorySink {
  final List<String> lines = <String>[];

  @override
  Future<void> writeLine(String line) async => lines.add(line);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  List<Map<String, dynamic>> get records => <Map<String, dynamic>>[
    for (final String l in lines) jsonDecode(l) as Map<String, dynamic>,
  ];
}

/// A clock that advances [step] every time it is read.
class _SteppingClock {
  _SteppingClock(this.step);
  final Duration step;
  DateTime _now = DateTime.utc(2026, 10, 17);
  DateTime call() => _now = _now.add(step);
}

/// Plays a script of decisions and exceptions, one per decide call.
class _ScriptedProvider extends ModelProvider {
  _ScriptedProvider(this.script);
  final List<Object> script;
  int _i = 0;

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    vision: false,
    preserveThinking: false,
    maxContext: 8000,
    supportsToolUse: true,
  );

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final Object next = script[_i++];
    if (next is ModelDecision) return next;
    throw next;
  }
}

class _Host implements LoopHost {
  @override
  String get agentsMd => 'AGENTS';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async => Observation.empty();

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async => <String, dynamic>{'ok': true};

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}

  @override
  void disableExtension(String namespace, String reason) {}

  @override
  List<ToolDescriptor> mergedTools() => const <ToolDescriptor>[
    ToolDescriptor(
      name: 'core.wait',
      description: 'wait',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    ToolDescriptor(
      name: 'core.done',
      description: 'done',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'reason': <String, dynamic>{'type': 'string'},
        },
        'additionalProperties': false,
      },
    ),
  ];

  @override
  Set<String> activeExtensionNamespaces() => const <String>{};
}

ModelCallUsage _usage(
  int input,
  int output, {
  String provider = 'anthropic',
  String model = 'claude-sonnet-4-6',
  int ttft = 0,
}) => ModelCallUsage(
  provider: provider,
  model: model,
  inputTokens: input,
  outputTokens: output,
  timeToFirstTokenMs: ttft,
);

ModelDecision _wait(ModelCallUsage usage) => ModelDecision(
  action: (tool: 'core.wait', args: <String, dynamic>{}),
  usage: usage,
);

ModelDecision _done(ModelCallUsage usage) => ModelDecision(
  action: (tool: 'core.done', args: <String, dynamic>{'reason': 'ok'}),
  usage: usage,
);

Future<(LoopDriver, _MemorySink)> _driver(
  List<Object> script, {
  ModelPricing pricing = ModelPricing.defaults,
}) async {
  final _MemorySink sink = _MemorySink();
  final TrajectoryWriter writer = TrajectoryWriter(sink);
  await writer.writeHeader(
    const SessionHeader(
      goal: 'goal',
      agentsMdHash: 'h',
      buildIdentifier: 'build',
      modelIdentifier: 'fake',
      harnessVersion: '0.1',
      extensions: <ExtensionManifestRecord>[],
      config: <String, dynamic>{},
    ),
  );
  final _Host host = _Host();
  final _SteppingClock clock = _SteppingClock(
    const Duration(milliseconds: 100),
  );
  final LoopDriver driver = LoopDriver(
    host: host,
    provider: _ScriptedProvider(script),
    conversation: ConversationBuilder(
      systemMessage: 'sys',
      tools: host.mergedTools(),
    ),
    validator: const ActionValidator(),
    writer: writer,
    providerRetryBackoff: Duration.zero,
    clock: clock.call,
    pricing: pricing,
  );
  return (driver, sink);
}

void main() {
  test('a schema retry is two billed calls on one turn', () async {
    final (LoopDriver driver, _MemorySink sink) = await _driver(<Object>[
      SchemaRejection(
        validationError: 'no tool call',
        rawOutput: 'hmm',
        usage: _usage(1000, 40),
      ),
      _wait(_usage(1100, 30)),
    ]);

    await driver.runTurn();

    final Map<String, dynamic> usage =
        sink.records.last['model_metadata']['usage'] as Map<String, dynamic>;
    expect(usage['model_calls'], 2);
    expect(usage['input_tokens'], 2100);
    expect(usage['output_tokens'], 70);
    expect(usage['model_latency_ms'], 200);
    expect(
      (usage['calls'] as List<dynamic>).map((dynamic c) => c['outcome']),
      <String>['schema_rejection', 'ok'],
    );
  });

  test(
    'a transport failure is a call without usage on a failed turn',
    () async {
      final (LoopDriver driver, _MemorySink sink) = await _driver(<Object>[
        const SocketException('connection reset'),
      ]);

      await expectLater(driver.runTurn(), throwsA(isA<TurnFailure>()));

      final Map<String, dynamic> turn = sink.records.last;
      expect(turn['validation']['reason'], 'provider_transport');
      final Map<String, dynamic> usage =
          turn['model_metadata']['usage'] as Map<String, dynamic>;
      expect(usage['model_calls'], 1);
      expect(usage['calls_without_usage'], 1);
      expect(usage.containsKey('input_tokens'), isFalse);
      expect(
        (usage['calls'] as List<dynamic>).single['outcome'],
        'transport_error',
      );
    },
  );

  test('the footer totals every call and prices a hosted model', () async {
    final (LoopDriver driver, _MemorySink sink) = await _driver(<Object>[
      _wait(_usage(400000, 20000, ttft: 50)),
      SchemaRejection(
        validationError: 'bad args',
        rawOutput: '{}',
        usage: _usage(500000, 10000, ttft: 50),
      ),
      _done(_usage(100000, 20000, ttft: 50)),
    ]);

    final SessionTermination t = await driver.runSession();
    expect(t.outcome, SessionOutcome.done);

    final Map<String, dynamic> footer = sink.records.last;
    expect(footer['type'], 'footer');
    final Map<String, dynamic> usage = footer['usage'] as Map<String, dynamic>;
    expect(usage['provider'], 'anthropic');
    expect(usage['model'], 'claude-sonnet-4-6');
    expect(usage['model_calls'], 3);
    expect(usage['input_tokens'], 1000000);
    expect(usage['output_tokens'], 50000);
    expect(usage['model_latency_ms'], 300);
    expect(usage['mean_time_to_first_token_ms'], 50);
    // 50k output tokens over 3 × (100 − 50) ms of generation.
    expect(usage['output_tokens_per_second'], closeTo(333333.33, 0.01));
    // Sonnet 4.6: 1M input at $3 + 50k output at $15/M.
    expect(usage['estimated_cost_usd'], closeTo(3.75, 1e-9));
    expect(usage['price'], <String, dynamic>{
      'input_per_mtok': 3.0,
      'output_per_mtok': 15.0,
      'source': 'built-in ${ModelPricing.defaultsAsOf}',
    });
    expect(driver.usage.calls, hasLength(3));
  });

  test('a local swift-infer run reports cost as unset, not zero', () async {
    final (LoopDriver driver, _MemorySink sink) = await _driver(<Object>[
      _done(_usage(5000, 300, provider: 'swift-infer', model: 'qwen')),
    ]);

    await driver.runSession();

    final Map<String, dynamic> usage =
        sink.records.last['usage'] as Map<String, dynamic>;
    expect(usage['input_tokens'], 5000);
    expect(usage.containsKey('estimated_cost_usd'), isTrue);
    expect(usage['estimated_cost_usd'], isNull);
    expect(usage.containsKey('price'), isFalse);
  });

  test('an override prices any model, local ones included', () async {
    final (LoopDriver driver, _MemorySink sink) = await _driver(
      <Object>[
        _done(_usage(2000000, 1000000, provider: 'swift-infer', model: 'qwen')),
      ],
      pricing: const ModelPricing(
        override: ModelPrice(inputPerMTok: 0.1, outputPerMTok: 0.5),
      ),
    );

    await driver.runSession();

    final Map<String, dynamic> usage =
        sink.records.last['usage'] as Map<String, dynamic>;
    expect(usage['estimated_cost_usd'], closeTo(0.7, 1e-9));
    expect(usage['price']['source'], 'override');
  });

  test('an unknown hosted model has no price', () {
    expect(
      ModelPricing.defaults.priceFor(provider: 'openai', model: 'gpt-9'),
      isNull,
    );
    expect(
      ModelPricing.defaults.priceFor(provider: 'openai', model: 'gpt-5'),
      isA<ModelPrice>(),
    );
  });

  test('SessionFooter round-trips its usage', () {
    const SessionFooter footer = SessionFooter(
      outcome: SessionOutcome.done,
      totalTurns: 2,
      totalDurationMs: 900,
      usage: <String, dynamic>{'model_calls': 2, 'estimated_cost_usd': null},
    );
    final SessionFooter back = SessionFooter.fromJson(
      jsonDecode(jsonEncode(footer.toJson())) as Map<String, dynamic>,
    );
    expect(back.usage, <String, dynamic>{
      'model_calls': 2,
      'estimated_cost_usd': null,
    });
  });

  test('ModelDecision carries usage across the provider wire', () {
    final ModelDecision d = _wait(_usage(10, 2, ttft: 7));
    final ModelDecision back = ModelDecision.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(back.usage, d.usage);
    expect(back, d);
  });
}
