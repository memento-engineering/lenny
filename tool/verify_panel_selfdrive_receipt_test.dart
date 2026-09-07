import 'dart:io';

import 'package:test/test.dart';

import 'verify_panel_selfdrive_receipt.dart'
    show
        ReceiptInvalid,
        assertInnerModelResolved,
        kSecretNames,
        probeDiagnostics,
        receiptDiagnostics,
        redactCapturesInPlace,
        redactSecrets,
        resolvedInnerModelId,
        terminalSessionTransitionObserved;

Map<String, dynamic> _markerTurn(String label) => <String, dynamic>{
  'type': 'turn',
  'observation': <String, dynamic>{
    'core': <String, dynamic>{
      'nodes': <dynamic>[
        <String, dynamic>{'label': label},
      ],
    },
  },
  'proposed_action': <String, dynamic>{'tool': 'core.wait'},
};

List<Map<String, dynamic>> _trajectory(String? resolvedModelId) =>
    <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'turn',
        'observation': <String, dynamic>{
          'core': <String, dynamic>{
            'nodes': <dynamic>[
              <String, dynamic>{'label': 'Stop'},
              if (resolvedModelId != null)
                <String, dynamic>{
                  'identifier': 'prompt.resolvedModel',
                  'label': 'Resolved model',
                  'value': resolvedModelId,
                },
            ],
          },
        },
        'proposed_action': <String, dynamic>{'tool': 'core.tap'},
      },
    ];

void main() {
  test('the endpoint is configuration, not a secret', () {
    expect(kSecretNames, isNot(contains('SWIFT_INFER_ENDPOINT')));
    expect(kSecretNames, contains('SWIFT_INFER_AGENT_TOKEN'));
  });

  test('a capture containing the endpoint passes clean', () async {
    final Directory dir = await Directory.systemTemp.createTemp('receipt-ok');
    addTearDown(() => dir.delete(recursive: true));
    final File capture = File('${dir.path}/panel.log')
      ..writeAsStringSync('connecting to https://swift.example/v1 ...');
    final Map<File, String> text = <File, String>{
      capture: capture.readAsStringSync(),
    };

    final List<String> leaked = await redactCapturesInPlace(
      text,
      const <String, String>{'SWIFT_INFER_AGENT_TOKEN': 'tok-abc'},
    );

    expect(leaked, isEmpty);
    expect(capture.readAsStringSync(), contains('https://swift.example/v1'));
  });

  test(
    'a capture containing the token is redacted in place, never deleted',
    () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'receipt-leak',
      );
      addTearDown(() => dir.delete(recursive: true));
      final File capture = File('${dir.path}/driver.log')
        ..writeAsStringSync('authorization: Bearer tok-abc\n');
      final Map<File, String> text = <File, String>{
        capture: capture.readAsStringSync(),
      };

      final List<String> leaked = await redactCapturesInPlace(
        text,
        const <String, String>{'SWIFT_INFER_AGENT_TOKEN': 'tok-abc'},
      );

      expect(leaked, <String>['SWIFT_INFER_AGENT_TOKEN']);
      expect(capture.existsSync(), isTrue);
      expect(
        capture.readAsStringSync(),
        contains('<REDACTED:SWIFT_INFER_AGENT_TOKEN>'),
      );
      expect(capture.readAsStringSync(), isNot(contains('tok-abc')));
      expect(text[capture], isNot(contains('tok-abc')));
    },
  );

  test('redactSecrets leaves unmatched text byte-identical', () {
    expect(
      redactSecrets('nothing here', const <String, String>{'A': 'zzz'}),
      'nothing here',
    );
  });

  test(
    'receiptDiagnostics counts turns, node-bearing turns and the footer',
    () {
      expect(
        receiptDiagnostics(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'turn',
            'observation': <String, dynamic>{
              'core': <String, dynamic>{'nodes': <dynamic>[]},
            },
            'proposed_action': <String, dynamic>{'tool': 'core.wait'},
          },
          <String, dynamic>{
            'type': 'turn',
            'observation': <String, dynamic>{
              'core': <String, dynamic>{
                'nodes': <dynamic>[
                  <String, dynamic>{'label': 'Start'},
                ],
              },
            },
            'proposed_action': <String, dynamic>{'tool': 'core.tap'},
          },
          <String, dynamic>{
            'type': 'footer',
            'outcome': 'harness_error',
            'harness_error': 'observation_envelope_rejected',
            'termination_detail': 'envelope_keys=[result, type]',
          },
        ]),
        <String>[
          'TURN_COUNT=2',
          'NON_EMPTY_NODE_TURN_COUNT=1',
          'LAST_PROPOSED_ACTION=core.tap',
          'FOOTER_OUTCOME=harness_error',
          'FOOTER_HARNESS_ERROR=observation_envelope_rejected',
          'FOOTER_TERMINATION_DETAIL=envelope_keys=[result, type]',
          'STOP_OBSERVED=false',
          'SELECT_MODEL_ERROR_OBSERVED=false',
          'INNER_PANEL_MODEL_RESOLVED=absent',
        ],
      );
    },
  );

  test(
    'receiptDiagnostics ignores a transient Stop and reports model error',
    () {
      expect(
        receiptDiagnostics(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'turn',
            'observation': <String, dynamic>{
              'core': <String, dynamic>{
                'nodes': <dynamic>[
                  <String, dynamic>{'label': 'Stop'},
                  <String, dynamic>{'label': 'Select a model'},
                ],
              },
            },
            'proposed_action': <String, dynamic>{'tool': 'core.tap'},
          },
        ]),
        containsAll(<String>[
          'STOP_OBSERVED=false',
          'SELECT_MODEL_ERROR_OBSERVED=true',
        ]),
      );
    },
  );

  test(
    'terminal marker transition is observed on the turn after Start without a Stop sample',
    () {
      final records = <Map<String, dynamic>>[
        _markerTurn('Session 0 · idle'),
        _markerTurn('Session 1 · done'),
      ];

      expect(terminalSessionTransitionObserved(records), isTrue);
      expect(receiptDiagnostics(records), contains('STOP_OBSERVED=true'));
      expect(receiptDiagnostics(records), contains('TURN_COUNT=2'));
      expect(
        records
            .expand(
              (record) =>
                  ((record['observation'] as Map)['core'] as Map)['nodes']
                      as List,
            )
            .whereType<Map<Object?, Object?>>()
            .any((node) => node['label'] == 'Stop'),
        isFalse,
      );
    },
  );

  test('terminal marker transition rejects insufficient evidence', () {
    final cases = <String, List<Map<String, dynamic>>>{
      'lone terminal marker': <Map<String, dynamic>>[
        _markerTurn('Session 1 · done'),
      ],
      'same generation': <Map<String, dynamic>>[
        _markerTurn('Session 1 · running'),
        _markerTurn('Session 1 · done'),
      ],
      'literal Stop without marker transition': <Map<String, dynamic>>[
        _markerTurn('Stop'),
      ],
      'decreasing generation': <Map<String, dynamic>>[
        _markerTurn('Session 2 · running'),
        _markerTurn('Session 1 · done'),
      ],
    };

    for (final MapEntry<String, List<Map<String, dynamic>>> entry
        in cases.entries) {
      expect(
        terminalSessionTransitionObserved(entry.value),
        isFalse,
        reason: entry.key,
      );
    }
  });

  test('receiptDiagnostics reports an empty trajectory without throwing', () {
    expect(
      receiptDiagnostics(const <Map<String, dynamic>>[]),
      containsAll(<String>[
        'TURN_COUNT=0',
        'NON_EMPTY_NODE_TURN_COUNT=0',
        'LAST_PROPOSED_ACTION=none',
        'FOOTER_OUTCOME=absent',
      ]),
    );
  });

  test('probeDiagnostics surfaces the truncation marker byte counts', () {
    expect(
      probeDiagnostics(
        '{"observation":{"type":"Response","value":{"_truncated":true,'
        '"originalBytes":4384,"budgetBytes":4096,"extensions":{}}}}',
      ),
      <String>[
        'PANEL_PROBE_OBSERVATION_KEYS='
            '_truncated,budgetBytes,extensions,originalBytes',
        'PANEL_PROBE_ORIGINAL_BYTES=4384',
        'PANEL_PROBE_BUDGET_BYTES=4096',
      ],
    );
  });

  test('probeDiagnostics reports absent for a missing probe', () {
    expect(probeDiagnostics(null), <String>[
      'PANEL_PROBE_OBSERVATION_KEYS=absent',
      'PANEL_PROBE_ORIGINAL_BYTES=absent',
      'PANEL_PROBE_BUDGET_BYTES=absent',
    ]);
  });

  test(
    'receiptDiagnostics surfaces a provider_transport termination detail',
    () {
      expect(
        receiptDiagnostics(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'footer',
            'outcome': 'harness_error',
            'harness_error': 'agent_stuck',
            'termination_detail':
                'provider_transport: ClientException; provider_request_id=req-7',
          },
        ]),
        containsAll(<String>[
          'FOOTER_HARNESS_ERROR=agent_stuck',
          'FOOTER_TERMINATION_DETAIL=provider_transport: ClientException; '
              'provider_request_id=req-7',
        ]),
      );
    },
  );

  test('the resolved inner model is read from the observation', () {
    expect(
      resolvedInnerModelId(_trajectory('qwen3.8-27b-8bit')),
      'qwen3.8-27b-8bit',
    );
    expect(
      assertInnerModelResolved(
        _trajectory('qwen3.8-27b-8bit'),
        'qwen3.8-27b-8bit',
      ),
      'qwen3.8-27b-8bit',
    );
  });

  test(
    'a picker label disagreeing with the requested id fails the receipt',
    () {
      expect(
        () => assertInnerModelResolved(
          _trajectory('qwen3.6-35b-a3b-8bit'),
          'qwen3.8-27b-8bit',
        ),
        throwsA(
          isA<ReceiptInvalid>().having(
            (ReceiptInvalid e) => e.message,
            'message',
            allOf(
              contains('qwen3.6-35b-a3b-8bit'),
              contains('qwen3.8-27b-8bit'),
            ),
          ),
        ),
      );
    },
  );

  test('receiptDiagnostics surfaces an unclassified harness error', () {
    expect(
      receiptDiagnostics(<Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'footer',
          'outcome': 'harness_error',
          'harness_error': 'unclassified',
          'termination_detail': '_UnknownHarnessFault: unknown harness fault',
        },
      ]),
      containsAll(<String>[
        'FOOTER_HARNESS_ERROR=unclassified',
        'FOOTER_TERMINATION_DETAIL=_UnknownHarnessFault: unknown harness fault',
      ]),
    );
  });

  test('a missing readout and an unset request both fail LOUDLY', () {
    expect(resolvedInnerModelId(_trajectory(null)), isNull);
    expect(
      () => assertInnerModelResolved(_trajectory(null), 'qwen3.8-27b-8bit'),
      throwsA(isA<ReceiptInvalid>()),
    );
    expect(
      () => assertInnerModelResolved(_trajectory('qwen3.8-27b-8bit'), ''),
      throwsA(isA<ReceiptInvalid>()),
    );
  });

  test('receiptDiagnostics surfaces the observed resolved model', () {
    expect(
      receiptDiagnostics(_trajectory('qwen3.8-27b-8bit')),
      contains('INNER_PANEL_MODEL_RESOLVED=qwen3.8-27b-8bit'),
    );
  });
}
