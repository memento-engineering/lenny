/// End-to-end provider-loop integration test for the exploration agent
/// (bead lenny-cx6.41).
///
/// Sibling to `packages/exploration_flutter/test/binding_e2e_integration_test.dart`
/// (lenny-cvl.4): cvl.4 closed the binding-side wire gap; this file
/// closes the provider-side gap by driving a real [ExplorationSession]
/// against a real [SwiftInferModelProvider] whose `http.Client` is a
/// `package:http/testing.dart` [MockClient.streaming] replaying canned
/// SSE bodies. The two tests together cover the agent's entire wire
/// surface (binding above + inference server below) without booting
/// the DevTools extension or a real model server.
///
/// Each scenario encodes one class of model misbehavior previously only
/// reproducible through the DevTools dogfood path (rebuild, restart,
/// click Start, read minified JS stack traces). The
/// `unknownToolBareNavigate` scenario is the direct regression for the
/// swift-infer trace `msg_333DE0C006B` (qwen3.6-27b returned
/// `"navigate"` without the `router_` prefix); after cx6.40 the
/// provider fails closed at the unknown-tool guard with
/// [SchemaRejection] before the call ever reaches the binding.
///
/// ## Scenarios (registered on `_Scenario.values`)
///
/// | id                       | shape                                                        | locks                                            |
/// |--------------------------|--------------------------------------------------------------|--------------------------------------------------|
/// | `happyPathSwiftInfer`    | well-formed `tool_use{name: router_navigate, ...}`           | baseline: encoded wire name routes end-to-end.    |
/// | `unknownToolBareNavigate`| bare `tool_use{name: navigate, ...}` (no namespace prefix)   | regression for swift-infer `msg_333DE0C006B` — fail closed at unknown-tool guard. |
/// | `malformedSseLine`       | one `data: {not valid json` chunk + a well-formed tool_use   | forward guard: malformed wire surfaces FormatException. |
/// | `noToolUseBlock`         | text-only stream, no `content_block_start` of type tool_use  | forward guard: provider rejects with SchemaRejection. |
/// | `midStreamDone`          | tool_use start then `[DONE]` before `input_json_delta`       | regression-lock for current bubble-through path. |
///
/// All five scenarios are forward-looking guards after cx6.40 landed.
/// The `unknownToolBareNavigate` scenario locks the regression by
/// asserting [SchemaRejection] is thrown before the call ever reaches
/// the binding.
///
/// ## Provider reuse
///
/// `expectScenario` is typed against [SwiftInferModelProvider] today
/// because that is the provider whose trace produced this bead's
/// regression. The fixture surface (`_sse`, `_toolUseSse`,
/// `_streamingMock`, the [_Scenario] registry) is intentionally
/// provider-agnostic: every Anthropic-compat
/// [ModelProvider] in the repo (the swift-infer gateway, the
/// `AnthropicProvider`, the `OpenAIProvider`) parses the same
/// `tool_use{name, input}` content-block shape through
/// `frontier/tool_helpers.dart`. cx6.40 flipped the
/// `unknownToolBareNavigate` matcher to
/// `throwsA(isA<SchemaRejection>())`; future widening of
/// `expectScenario`'s `provider:` parameter from the concrete
/// `SwiftInferModelProvider` to the [ModelProvider] interface remains
/// a touch-this-file-only change.
///
/// ## Sibling fakes
///
/// The in-process [VmService] bridge is the shared
/// `BindingVmServiceFake` from
/// `package:exploration_flutter/test_support/binding_vm_service_fake.dart`
/// (hoisted by lenny-imr). Any wire-contract change in `cvl.*`
/// (extension prefixes, `args` encoding, RPC error codes) updates the
/// single shared class — no manual mirror discipline anymore.
// The test-private `expectScenario` helper accepts a private `_Scenario`
// parameter; both stay file-private to keep the registry from leaking
// out of the test. cx6.40 will widen the helper without unprivatizing.
// ignore_for_file: library_private_types_in_public_api
library;

import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../_support/exploration_vm_service_fake.dart';


/// Serialise [events] into the `data: <json>\n\n` SSE wire form the
/// Anthropic-compat providers (swift-infer / Anthropic / OpenAI) all
/// consume. Cribbed verbatim from
/// `packages/exploration_agent/test/provider/swift_infer/swift_infer_provider_test.dart`
/// so the two suites parse identical fixtures.
String _sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

/// Build a complete SSE body that announces a single `tool_use`
/// content block with [name] (wire form, e.g. `router_navigate`) and
/// [input] (the JSON-encoded tool args).
///
/// Defaults mirror the most common shape: a single `router_navigate`
/// block with a `route_name` string argument. Scenarios that need to
/// produce a malformed wire (bare tool name, missing tool_use block,
/// truncated stream, ...) inline their own bodies using [_sse] and
/// string concatenation rather than extending this helper.
String _toolUseSse({
  String name = 'router_navigate',
  Map<String, dynamic> input = const <String, dynamic>{
    'route_name': 'settings',
  },
}) => _sse(<Map<String, dynamic>>[
  <String, dynamic>{
    'type': 'content_block_start',
    'content_block': <String, dynamic>{
      'type': 'tool_use',
      'id': 't1',
      'name': name,
    },
  },
  <String, dynamic>{
    'type': 'content_block_delta',
    'delta': <String, dynamic>{
      'type': 'input_json_delta',
      'partial_json': jsonEncode(input),
    },
  },
  <String, dynamic>{'type': 'message_stop'},
]);

/// Wrap [body] in a [MockClient.streaming] producing a 200 SSE response.
///
/// The handler returns a single-chunk stream of [body] as utf-8 bytes;
/// the provider's `LineSplitter` slices it into SSE lines exactly as it
/// would on the wire from a live server.
MockClient _streamingMock(String body) => MockClient.streaming(
  (req, bodyStream) async => http.StreamedResponse(
    Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
    200,
    headers: <String, String>{'content-type': 'text/event-stream'},
  ),
);

/// Tool descriptor matching the production-realistic qualified name
/// (`router.navigate`) the test plugin contributes via the registry.
/// Default tools list for every scenario, including
/// `unknownToolBareNavigate`: the unprefixed wire name `'navigate'` no
/// longer resolves via `lookupTool`, so after cx6.40 the provider
/// throws [SchemaRejection] at the unknown-tool guard before the call
/// ever reaches `VmServiceClient.executeAction`.
final ToolDescriptor _routerNavigateDescriptor = ToolDescriptor(
  name: 'router.navigate',
  description: 'navigate to the named route',
  inputSchema: const <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'route_name': <String, dynamic>{'type': 'string'},
    },
    'required': <String>['route_name'],
    'additionalProperties': false,
  },
);

/// One end-to-end fixture exercising a specific class of model
/// behaviour against the full provider → session → binding loop.
///
/// Each scenario bundles the SSE body the fake `http.Client` will
/// stream back, the matcher [outcome] applied to the
/// `provider.decide → session.act` chain, and a [regressionNote] tying
/// the case to the real-world misbehavior it locks in. New scenarios
/// should add a matching entry to [_Scenario.values] so the main()
/// loop picks them up automatically.
class _Scenario {
  _Scenario({
    required this.id,
    required this.body,
    required this.outcome,
    required this.regressionNote,
    List<ToolDescriptor>? tools,
  }) : tools = tools ?? <ToolDescriptor>[_routerNavigateDescriptor];

  /// Human-readable identifier; used for the `test(...)` description and
  /// for `--plain-name` filtering during validation.
  final String id;

  /// SSE wire body the fake `http.Client` returns.
  final String body;

  /// Matcher applied to the future returned by
  /// `provider.decide(...).then((d) => session.act(...))`.
  final Matcher outcome;

  /// One-liner describing the regression or forward-looking guard.
  final String regressionNote;

  /// Tool descriptors fed to both the provider's prompt and the
  /// `ActionSchema`. Defaults to the production-realistic
  /// `[router.navigate]`; every current scenario uses the default
  /// (the `unknownToolBareNavigate` regression now relies on the
  /// unprefixed wire name *not* resolving against this list so the
  /// provider's unknown-tool guard fires).
  final List<ToolDescriptor> tools;

  /// Happy path — provider emits a well-formed
  /// `tool_use{name: 'router_navigate', input: {route_name: 'settings'}}`;
  /// the session routes the call through the binding and the test plugin
  /// records exactly one invocation with `route_name == 'settings'`.
  static final _Scenario happyPath = _Scenario(
    id: 'happyPathSwiftInfer',
    body: _toolUseSse(),
    outcome: completion(
      predicate<Map<String, dynamic>>(
        (r) => r['ok'] == true && r['value'] == 'settings',
        'tool result {ok: true, value: settings}',
      ),
    ),
    regressionNote:
        'baseline: encoded tool name (router_navigate) decodes to router.navigate '
        'and routes through invokePluginTool.',
  );

  /// Regression for swift-infer trace `msg_333DE0C006B` — provider
  /// emits the bare token `'navigate'` (no `router_` namespace prefix).
  /// `lookupTool('navigate', [router.navigate])` returns null, so
  /// `frontier/tool_helpers.dart`'s `unknownToolRejection` fires and
  /// the provider throws [SchemaRejection] before the call ever
  /// reaches `session.act` (and therefore never reaches the binding or
  /// cvl.3's qualified-name guard). The scenario uses the default
  /// `[router.navigate]` tool list — no override — so the unknown-tool
  /// guard is what trips, exactly mirroring the production wire shape.
  static final _Scenario unknownToolBareNavigate = _Scenario(
    id: 'unknownToolBareNavigate',
    body: _toolUseSse(name: 'navigate'),
    outcome: throwsA(
      isA<SchemaRejection>().having(
        (SchemaRejection e) => e.validationError,
        'validationError',
        startsWith('model emitted unknown tool: navigate'),
      ),
    ),
    regressionNote:
        'swift-infer msg_333DE0C006B: model returned "navigate" without '
        'the namespace prefix; provider now fails closed with '
        'SchemaRejection before reaching the binding.',
  );

  /// One SSE line is unparseable JSON (`data: {not valid json`); the
  /// provider's `jsonDecode` of that payload throws [FormatException]
  /// with the offending fragment in its message. Locks the
  /// "fail loud on malformed wire" behaviour so regressions don't
  /// silently swallow the bad chunk.
  static final _Scenario malformedSseLine = _Scenario(
    id: 'malformedSseLine',
    body: 'data: {not valid json\n\n${_toolUseSse(name: 'router_navigate')}',
    // FormatException from jsonDecode reports the parser failure on
    // `.message` (e.g. "Unexpected character") and the raw offending
    // text on `.source`. Assert against `.toString()` so the matcher
    // covers both the parser message and the offending payload — that
    // is the failure shape a caller actually sees in a stack trace.
    outcome: throwsA(
      isA<FormatException>().having(
        (FormatException e) => e.toString(),
        'toString',
        contains('not valid json'),
      ),
    ),
    regressionNote:
        'malformed wire: a single bad SSE chunk must surface a '
        'FormatException carrying the offending payload.',
  );

  /// Stream contains only `text_delta` events and `message_stop`; no
  /// `content_block_start` of type `tool_use` ever arrives. The
  /// provider raises
  /// `SchemaRejection(validationError: 'no tool_use block in response')`
  /// — the canonical "model forgot to call a tool" guard.
  static final _Scenario noToolUseBlock = _Scenario(
    id: 'noToolUseBlock',
    body: _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{'type': 'text_delta', 'text': 'hello'},
      },
      <String, dynamic>{'type': 'message_stop'},
    ]),
    outcome: throwsA(
      isA<SchemaRejection>().having(
        (SchemaRejection e) => e.validationError,
        'validationError',
        'no tool_use block in response',
      ),
    ),
    regressionNote:
        'tool-use omission: model replied with plain text only; provider '
        'must reject with the canonical SchemaRejection message.',
  );

  /// Stream announces a `tool_use` block then sends `data: [DONE]`
  /// before any `input_json_delta` arrives. `input_json_delta` is never
  /// accumulated, the JSON-decode branch is skipped, and the resulting
  /// empty-args envelope fails the action-schema's required-arg check
  /// → [SchemaRejection]. Locks the current bubble-through path so
  /// future stream-termination handling doesn't regress silently.
  static final _Scenario midStreamDone = _Scenario(
    id: 'midStreamDone',
    body:
        '${_sse(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'content_block_start',
            'content_block': <String, dynamic>{'type': 'tool_use', 'id': 't1', 'name': 'router_navigate'},
          },
        ])}data: [DONE]\n\n',
    outcome: throwsA(isA<SchemaRejection>()),
    regressionNote:
        'mid-stream [DONE]: provider receives tool_use start with no '
        'input_json_delta — currently surfaces as SchemaRejection.',
  );

  /// Iteration order is the order each scenario was authored; main()
  /// emits one `test(...)` block per entry.
  static final List<_Scenario> values = <_Scenario>[
    happyPath,
    unknownToolBareNavigate,
    malformedSseLine,
    noToolUseBlock,
    midStreamDone,
  ];
}

/// Drive one full provider → session → binding turn for [scenario] and
/// apply its [outcome] matcher to the chain.
///
/// The closure runs `provider.decide(...)` followed by
/// `session.act(...)` — any throw from either step propagates to the
/// matcher. cx6.40's validation step will reuse this entry point to
/// re-assert the unknown-tool case as [SchemaRejection]; keep the
/// `tools` parameter injected (not a hardcoded const) so callers can
/// extend the fixture's tool list without forking this helper.
///
/// Typed against [SwiftInferModelProvider] today; cx6.40 may widen the
/// signature to [ModelProvider] once the Anthropic / OpenAI variants
/// are parametrised over the same scenario registry.
Future<void> expectScenario({
  required ExplorationSession session,
  required SwiftInferModelProvider provider,
  required _Scenario scenario,
  List<ToolDescriptor> tools = const <ToolDescriptor>[],
}) async {
  Future<Map<String, dynamic>> run() async {
    final builder = ConversationBuilder(systemMessage: 'sys', tools: tools);
    builder.appendUserTurn(Observation.empty(), ObservationDiff.empty());
    final ModelDecision d = await provider.decide(
      builder.snapshot(),
      ActionSchema.fromToolList(tools),
    );
    return session.act(<String, dynamic>{
      'name': d.action.tool,
      'args': d.action.args,
    });
  }

  await expectLater(run(), scenario.outcome);
}

/// Build a fresh [SwiftInferModelProvider] backed by a [MockClient.streaming]
/// returning [body]. Defaults mirror swift-infer's smallest meaningful
/// config (`localhost:8080` + `'test'` model); scenarios don't override
/// because the provider's HTTP plumbing is what we're exercising, not
/// the sampling knobs.
SwiftInferModelProvider _buildProvider(String body) => SwiftInferModelProvider(
  config: SwiftInferConfig(
    baseUrl: Uri.parse('http://localhost:8080'),
    model: 'test',
  ),
  client: _streamingMock(body),
);

void main() {
  late ExplorationVmServiceFake fake;
  late List<Map<String, dynamic>> routerCalls;

  setUpAll(() async {
    routerCalls = <Map<String, dynamic>>[];
    fake = ExplorationVmServiceFake(
      handshakeResponse: <String, dynamic>{
        'protocolVersion': '1',
        'plugins': <dynamic>[
          <String, dynamic>{
            'namespace': 'router',
            'tools': <String>['navigate'],
          },
        ],
      },
      observationBundle: <String, dynamic>{
        'semantics': <dynamic>[],
        'routes': <String>['login'],
        'errors': <dynamic>[],
        'stability': <String, dynamic>{
          'policy': 'action_relative',
          'reason': 'idle',
        },
        'plugins': <String, dynamic>{},
      },
      handlers: <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>?)>{
        'ext.flutter.exploration.router.navigate': (args) async {
          // args arrive JSON-encoded from VmServiceClient.executeAction;
          // decode the route_name value before storing.
          final String? raw = args?['route_name'] as String?;
          final Object? routeName = raw != null ? jsonDecode(raw) : null;
          routerCalls.add(<String, dynamic>{'route_name': routeName});
          return <String, dynamic>{'ok': true, 'value': routeName};
        },
      },
    );
  });

  setUp(() {
    routerCalls.clear();
    fake.calls.clear();   // reset recorded RPC calls between scenarios
  });

  tearDownAll(() async {
    await fake.dispose();
  });

  for (final _Scenario scenario in _Scenario.values) {
    test('provider loop scenario: ${scenario.id}', () async {
      final SwiftInferModelProvider provider = _buildProvider(scenario.body);
      // ExplorationVmServiceFake is a VmService; fromVmService accepts VmService.
      final ExplorationSession session = ExplorationSession.fromVmService(
        fake,
        'isolate-0',
      );
      await session.start('exploration goal', const ExplorationConfig());
      await expectScenario(
        session: session,
        provider: provider,
        scenario: scenario,
        tools: scenario.tools,
      );

      if (identical(scenario, _Scenario.happyPath)) {
        expect(routerCalls, hasLength(1));
        expect(routerCalls.single['route_name'], 'settings');
      } else {
        expect(routerCalls, isEmpty);
      }
      // end() is not strictly required here since the session's VmService
      // is the shared fake (not a real socket), but call it for hygiene.
      await session.end();
    });
  }
}
