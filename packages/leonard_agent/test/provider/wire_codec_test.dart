import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

const SemanticsNode _previousNode = SemanticsNode(
  id: 7,
  role: 'button',
  label: 'Continue',
  identifier: 'checkout.continue',
  value: 'ready',
  hint: 'Advance to payment',
  state: <String>['enabled'],
  actions: <String>['tap'],
  rect: <int>[10, 20, 110, 70],
  scroll: <String, int>{'pos': 0, 'min': 0, 'max': 200},
);

const SemanticsNode _currentNode = SemanticsNode(
  id: 7,
  role: 'button',
  label: 'Pay now',
  identifier: 'checkout.continue',
  value: 'ready',
  hint: 'Submit payment',
  state: <String>['enabled', 'focused'],
  actions: <String>['tap'],
  rect: <int>[10, 20, 110, 70],
  scroll: <String, int>{'pos': 100, 'min': 0, 'max': 200},
);

const SemanticsNode _addedNode = SemanticsNode(
  id: 9,
  role: 'textField',
  label: 'Card number',
  value: '•••• 4242',
  state: <String>['enabled'],
  actions: <String>['setText'],
  rect: <int>[10, 90, 310, 140],
);

final Observation _observation = Observation(
  core: const CoreFragment(
    routeStack: <String>['/checkout', '/cart'],
    nodes: <int, SemanticsNode>{7: _currentNode},
    errors: <RuntimeError>[
      RuntimeError(
        seq: 4,
        message: 'payment retry scheduled',
        frames: <String>['checkout.dart:42', 'app.dart:10'],
        wallClockOffsetMs: 125,
      ),
    ],
  ),
  extensions: const <String, ExtensionFragment>{
    'router': ExtensionFragment(
      namespace: 'router',
      data: <String, dynamic>{
        'route': '/checkout',
        'history': <Object?>['/cart', '/checkout'],
        'flags': <String, dynamic>{'restorable': true, 'token': null},
      },
      deltaFriendly: true,
    ),
  },
  stability: const StabilityMetadata(
    policy: 'idle',
    terminatedBy: 'framework_idle',
    durationMs: 38,
    frameworkBusy: <String, dynamic>{
      'frames': 2,
      'phases': <String>['build', 'paint'],
    },
    extensionsBusy: <ExtensionBusy>[
      ExtensionBusy(namespace: 'router', reason: 'transition', estMs: 5),
    ],
  ),
  screenshot: 'iVBORw0KGgo=',
);

final ObservationDiff _diff = ObservationDiff(
  core: const CoreDiff(
    routeChanges: <RouteChange>[
      RouteChange(
        previous: <String>['/cart'],
        current: <String>['/checkout', '/cart'],
      ),
    ],
    nodesAdded: <SemanticsNode>[_addedNode],
    nodesRemoved: <int>[3],
    nodesChanged: <NodeChange>[
      NodeChange(prev: _previousNode, curr: _currentNode),
    ],
    errorsAdded: <RuntimeError>[
      RuntimeError(
        seq: 4,
        message: 'payment retry scheduled',
        frames: <String>['checkout.dart:42'],
        wallClockOffsetMs: 125,
      ),
    ],
  ),
  extensions: const <String, ExtensionDiff>{
    'structured': ExtensionDiffStructured(
      added: <String, dynamic>{
        'status': 'ready',
        'nested': <String, dynamic>{'count': 2},
      },
      removed: <String, dynamic>{'stale': true},
      changed: <String, ChangedValue>{
        'step': ChangedValue(prev: 1, curr: 2),
        'options': ChangedValue(
          prev: <String>['card'],
          curr: <String>['card', 'cash'],
        ),
      },
    ),
    'opaque': ExtensionDiffOpaque(
      previous: <String, dynamic>{
        'value': <int>[1, 2],
      },
      current: <String, dynamic>{
        'value': <int>[2, 3],
      },
    ),
    'added': ExtensionDiffAdded(current: <String, dynamic>{'enabled': true}),
    'removed': ExtensionDiffRemoved(previous: null),
  },
);

const ToolDescriptor _tool = ToolDescriptor(
  name: 'checkout.pay',
  description: 'Submit the selected payment method.',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'method': <String, dynamic>{
        'type': 'string',
        'enum': <String>['card', 'cash'],
      },
      'receipt': <String, dynamic>{
        'type': <String>['object', 'null'],
        'properties': <String, dynamic>{
          'email': <String, dynamic>{'type': 'string'},
        },
      },
    },
    'required': <String>['method'],
    'additionalProperties': false,
  },
);

final UserTurn _userTurn = UserTurn(
  observation: _observation,
  diff: _diff,
  toolResult: <String, dynamic>{
    'ok': false,
    'details': <String, dynamic>{
      'codes': <Object?>['retry', null],
    },
  },
  trimmed: true,
);

final AssistantTurn _assistantTurn = AssistantTurn(
  thinking: 'The checkout is ready.',
  action: (
    tool: 'checkout.pay',
    args: <String, dynamic>{
      'method': 'card',
      'receipt': <String, dynamic>{'email': 'agent@example.test'},
    },
  ),
);

final ConversationSnapshot _snapshot = ConversationSnapshot(
  systemMessage: 'Complete checkout safely.',
  turns: <ConversationTurn>[_userTurn, _assistantTurn],
  tools: <ToolDescriptor>[_tool],
);

void main() {
  group('conversation wire codecs', () {
    test('nested observation and diff payloads are reversible', () {
      expect(Observation.fromJson(_observation.toJson()), _observation);

      final ObservationDiff decoded = ObservationDiff.fromJson(_diff.toJson());
      expect(decoded.toJson(), _diff.toJson());
      expect(decoded.extensions['structured'], isA<ExtensionDiffStructured>());
      expect(decoded.extensions['opaque'], isA<ExtensionDiffOpaque>());
      expect(decoded.extensions['added'], isA<ExtensionDiffAdded>());
      expect(decoded.extensions['removed'], isA<ExtensionDiffRemoved>());
    });

    test('tool descriptor uses snake_case and round-trips by value', () {
      expect(_tool.toJson(), <String, dynamic>{
        'name': 'checkout.pay',
        'description': 'Submit the selected payment method.',
        'input_schema': _tool.inputSchema,
      });
      expect(ToolDescriptor.fromJson(_tool.toJson()), _tool);
    });

    test('turn variants carry explicit discriminators and dispatch', () {
      final Map<String, dynamic> userJson = _userTurn.toJson();
      final Map<String, dynamic> assistantJson = _assistantTurn.toJson();

      expect(userJson.keys, <String>{
        'type',
        'observation',
        'diff',
        'tool_result',
        'trimmed',
      });
      expect(userJson['type'], 'user');
      expect(assistantJson, <String, dynamic>{
        'type': 'assistant',
        'thinking': 'The checkout is ready.',
        'action': <String, dynamic>{
          'tool': 'checkout.pay',
          'args': _assistantTurn.action.args,
        },
      });

      final ConversationTurn decodedUser = ConversationTurn.fromJson(userJson);
      final ConversationTurn decodedAssistant = ConversationTurn.fromJson(
        assistantJson,
      );
      expect(decodedUser, isA<UserTurn>());
      expect(decodedUser, _userTurn);
      expect(decodedAssistant, isA<AssistantTurn>());
      expect(decodedAssistant, _assistantTurn);
      expect(UserTurn.fromJson(userJson), _userTurn);
      expect(AssistantTurn.fromJson(assistantJson), _assistantTurn);
    });

    test('turn dispatch rejects missing and unknown discriminators', () {
      expect(
        () => ConversationTurn.fromJson(<String, dynamic>{}),
        throwsFormatException,
      );
      expect(
        () => ConversationTurn.fromJson(<String, dynamic>{'type': 'future'}),
        throwsFormatException,
      );
    });

    test('snapshot survives a JSON text boundary without data loss', () {
      final Map<String, dynamic> wire = _snapshot.toJson();
      expect(wire.keys, <String>{'system_message', 'turns', 'tools'});

      final Map<String, dynamic> decodedJson = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(wire)) as Map,
      );
      final ConversationSnapshot decoded = ConversationSnapshot.fromJson(
        decodedJson,
      );
      expect(decoded, _snapshot);
      expect(decoded.hashCode, _snapshot.hashCode);
      expect(decoded.turns, <Matcher>[isA<UserTurn>(), isA<AssistantTurn>()]);
    });

    test('empty lists and a null tool result round-trip', () {
      final ConversationSnapshot empty = ConversationSnapshot(
        systemMessage: 'empty',
        turns: <ConversationTurn>[
          UserTurn(
            observation: Observation.empty(),
            diff: ObservationDiff.empty(),
          ),
        ],
        tools: const <ToolDescriptor>[],
      );
      final Map<String, dynamic> turnJson = empty.turns.single.toJson();
      expect(turnJson, isNot(contains('tool_result')));
      expect(ConversationSnapshot.fromJson(empty.toJson()), empty);

      const ConversationSnapshot noTurns = ConversationSnapshot(
        systemMessage: 'none',
        turns: <ConversationTurn>[],
        tools: <ToolDescriptor>[],
      );
      expect(ConversationSnapshot.fromJson(noTurns.toJson()), noTurns);
      expect(
        ConversationSnapshot.fromJson(<String, dynamic>{
          'system_message': 'none',
        }),
        noTurns,
      );
    });

    test('unknown extension diff kinds are rejected', () {
      expect(
        () => ObservationDiff.fromJson(<String, dynamic>{
          'extensions': <String, dynamic>{
            'future': <String, dynamic>{'kind': 'future'},
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('model result wire codecs', () {
    test('decision omits null optionals and preserves empty metadata', () {
      final ModelDecision decision = ModelDecision(
        action: (tool: 'core.wait', args: <String, dynamic>{}),
      );
      expect(decision.toJson(), <String, dynamic>{
        'action': <String, dynamic>{
          'tool': 'core.wait',
          'args': <String, dynamic>{},
        },
        'model_metadata': <String, dynamic>{},
      });
      expect(ModelDecision.fromJson(decision.toJson()), decision);
    });

    test('decision preserves action, metadata, and every optional field', () {
      final ModelDecision decision = ModelDecision(
        action: (
          tool: 'checkout.pay',
          args: <String, dynamic>{
            'method': 'card',
            'receipt': <String, dynamic>{
              'email': 'agent@example.test',
              'tags': <Object?>['important', null],
            },
          },
        ),
        thinking: 'Payment is the next step.',
        rationale: 'The form is complete.',
        waitStrategy: 'idle',
        providerRequestId: 'msg_42',
        modelMetadata: <String, dynamic>{
          'served_model_id': 'model-v2',
          'usage': <String, dynamic>{'input_tokens': 12, 'cached': true},
        },
      );
      final Map<String, dynamic> json = decision.toJson();
      expect(json.keys, <String>{
        'action',
        'thinking',
        'rationale',
        'wait_strategy',
        'provider_request_id',
        'model_metadata',
      });
      expect(json['action'], <String, dynamic>{
        'tool': 'checkout.pay',
        'args': decision.action.args,
      });
      expect(ModelDecision.fromJson(json), decision);
      expect(ModelDecision.fromJson(json).hashCode, decision.hashCode);
    });

    test('thinking deltas round-trip in final and non-final forms', () {
      const ThinkingDelta partial = ThinkingDelta(
        text: 'considering',
        isFinal: false,
      );
      const ThinkingDelta finalDelta = ThinkingDelta(text: '', isFinal: true);

      expect(partial.toJson(), <String, dynamic>{
        'text': 'considering',
        'is_final': false,
      });
      expect(ThinkingDelta.fromJson(partial.toJson()), partial);
      expect(ThinkingDelta.fromJson(finalDelta.toJson()), finalDelta);
    });
  });

  test('action schema transports its document and rebuilds validation', () {
    final ActionSchema schema = ActionSchema.fromToolList(<ToolDescriptor>[
      _tool,
    ]);
    expect(identical(schema.toJson(), schema.jsonSchema), isTrue);

    final Map<String, dynamic> root = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(schema.toJson())) as Map,
    );
    final ActionSchema decoded = ActionSchema.fromJson(root);
    expect(decoded, schema);
    expect(decoded.hashCode, schema.hashCode);

    final Map<String, dynamic> valid = <String, dynamic>{
      'action': <String, dynamic>{
        'tool': 'checkout.pay',
        'args': <String, dynamic>{'method': 'card'},
      },
    };
    expect(decoded.validate(jsonEncode(valid)), valid);
    expect(
      () => decoded.validate(
        jsonEncode(<String, dynamic>{
          'action': <String, dynamic>{
            'tool': 'checkout.unknown',
            'args': <String, dynamic>{},
          },
        }),
      ),
      throwsA(isA<SchemaRejection>()),
    );
  });
}
