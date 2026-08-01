import 'package:leonard_flutter/src/observation/observation_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObservationRequest defaults', () {
    test('empty JSON yields all PRD §9.1 defaults', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{},
      );
      expect(r.policy, StabilityPolicy.actionRelative);
      expect(r.actionRelativeBudgetMs, 800);
      expect(r.quietFrameN, 2);
      expect(r.boundedStabilityBudgetMs, 1500);
      expect(r.includeScreenshot, isFalse);
      expect(r.extensionBudgets, isEmpty);
      expect(r.errorCursor, isNull);
    });
  });

  group('policy parsing', () {
    test('parses each wire token by name', () {
      expect(
        ObservationRequest.fromJson(<String, dynamic>{
          'policy': 'action-relative',
        }).policy,
        StabilityPolicy.actionRelative,
      );
      expect(
        ObservationRequest.fromJson(<String, dynamic>{
          'policy': 'quiet-frame',
        }).policy,
        StabilityPolicy.quietFrame,
      );
      expect(
        ObservationRequest.fromJson(<String, dynamic>{
          'policy': 'bounded-stability',
        }).policy,
        StabilityPolicy.boundedStability,
      );
    });

    test('throws FormatException on unknown policy', () {
      expect(
        () => ObservationRequest.fromJson(<String, dynamic>{'policy': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('budget clamping', () {
    test('actionRelativeBudgetMs > 30000 clamps to 30000', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{'actionRelativeBudgetMs': 60000},
      );
      expect(r.actionRelativeBudgetMs, 30000);
    });

    test('boundedStabilityBudgetMs > 30000 clamps to 30000', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{'boundedStabilityBudgetMs': 99999},
      );
      expect(r.boundedStabilityBudgetMs, 30000);
    });

    test('budgets at or below 30000 are preserved', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{
          'actionRelativeBudgetMs': 30000,
          'boundedStabilityBudgetMs': 1500,
        },
      );
      expect(r.actionRelativeBudgetMs, 30000);
      expect(r.boundedStabilityBudgetMs, 1500);
    });

    test('negative budgets clamp to zero (defence in depth)', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{'actionRelativeBudgetMs': -100},
      );
      expect(r.actionRelativeBudgetMs, 0);
    });
  });

  group('overrides and extensionBudgets', () {
    test('explicit overrides parse and preserve', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{
          'policy': 'quiet-frame',
          'quietFrameN': 4,
          'includeScreenshot': true,
          'extensionBudgets': <String, dynamic>{'a': 256, 'b': 512},
          'errorCursor': 7,
        },
      );
      expect(r.policy, StabilityPolicy.quietFrame);
      expect(r.quietFrameN, 4);
      expect(r.includeScreenshot, isTrue);
      expect(r.extensionBudgets['a'], 256);
      expect(r.extensionBudgets['b'], 512);
      expect(r.errorCursor, 7);
    });

    test('quietFrameN below 1 clamps up to 1', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{'quietFrameN': 0},
      );
      expect(r.quietFrameN, 1);
    });

    test('bad extensionBudgets entries are dropped, not propagated', () {
      final ObservationRequest r = ObservationRequest.fromJson(
        <String, dynamic>{
          'extensionBudgets': <String, dynamic>{
            'good': 100,
            'bad': 'not-a-number',
            'neg': -10,
          },
        },
      );
      expect(r.extensionBudgets, hasLength(1));
      expect(r.extensionBudgets['good'], 100);
    });
  });
}
