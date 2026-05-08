import 'dart:convert';

import 'package:exploration_dio/src/observation_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('small fragment passes through unchanged', () {
    final frag = <String, Object?>{
      'in_flight': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'req_0',
          'method': 'GET',
          'host': 'a.example.com',
          'path': '/x',
          'elapsed_ms': 10,
          'est_remaining_ms': 590,
        },
      ],
      'recent_completed': const <Object?>[],
    };
    final result = truncateToBudget(frag, kPluginBudgetBytes);
    expect(identical(result, frag), isTrue);
    expect(result.containsKey('truncated'), isFalse);
  });

  test('oversized fragment is truncated and tagged', () {
    Map<String, Object?> entry(int n) => <String, Object?>{
          'id': 'req_$n',
          'method': 'GET',
          'host': 'service-with-a-fairly-long-host-name.example.com',
          'path': '/api/v1/resources/$n/sub-resources/with-some-extra-padding',
          'elapsed_ms': n * 17,
          'est_remaining_ms': 600,
        };
    final completed = <Map<String, Object?>>[
      for (var n = 0; n < 50; n++)
        <String, Object?>{
          'id': 'req_$n',
          'method': 'GET',
          'host': 'service-with-a-fairly-long-host-name.example.com',
          'path': '/api/v1/resources/$n/sub-resources/with-some-extra-padding',
          'status': 200,
          'duration_ms': 480,
        },
    ];
    final frag = <String, Object?>{
      'in_flight': <Map<String, Object?>>[for (var n = 0; n < 50; n++) entry(n)],
      'recent_completed': completed,
    };

    final result = truncateToBudget(frag, kPluginBudgetBytes);
    expect(result['truncated'], isTrue);
    expect(utf8.encode(jsonEncode(result)).length, lessThanOrEqualTo(1024));
  });
}
