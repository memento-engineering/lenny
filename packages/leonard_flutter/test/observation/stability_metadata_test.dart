import 'package:leonard_flutter/src/observation/observation_request.dart';
import 'package:leonard_flutter/src/observation/stability_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminatedBy wire mapping', () {
    test('all enum values map to PRD §9.2 snake_case tokens', () {
      expect(kTerminatedByWireNames[TerminatedBy.routeChange], 'route_change');
      expect(
        kTerminatedByWireNames[TerminatedBy.semanticsChange],
        'semantics_change',
      );
      expect(kTerminatedByWireNames[TerminatedBy.idle], 'idle');
      expect(kTerminatedByWireNames[TerminatedBy.quietFrame], 'quiet_frame');
      expect(kTerminatedByWireNames[TerminatedBy.budget], 'budget');
      // Spot-check that every enum value has a token (no orphans).
      for (final TerminatedBy v in TerminatedBy.values) {
        expect(
          kTerminatedByWireNames[v],
          isNotNull,
          reason: '$v has no wire token',
        );
      }
    });
  });

  group('ExtensionBusy.toJson', () {
    test('omits null reason and estMs', () {
      const ExtensionBusy p = ExtensionBusy('plug');
      expect(p.toJson(), <String, Object?>{'namespace': 'plug'});
    });

    test('includes reason and est_ms when present', () {
      const ExtensionBusy p = ExtensionBusy('plug', reason: 'loading', estMs: 250);
      expect(p.toJson(), <String, Object?>{
        'namespace': 'plug',
        'reason': 'loading',
        'est_ms': 250,
      });
    });
  });

  group('StabilityMetadata.toJson', () {
    test('produces the PRD §9.2 stability block shape', () {
      final StabilityMetadata sm = StabilityMetadata(
        policy: StabilityPolicy.boundedStability,
        terminatedBy: TerminatedBy.budget,
        durationMs: 1234,
        frameworkBusy: const <String, Object?>{'transient_callbacks': 1},
        extensionsBusy: const <ExtensionBusy>[
          ExtensionBusy('a', reason: 'navigating', estMs: 100),
          ExtensionBusy('b'),
        ],
      );

      final Map<String, Object?> json = sm.toJson();
      expect(json['policy'], 'bounded-stability');
      expect(json['terminated_by'], 'budget');
      expect(json['duration_ms'], 1234);
      expect(json['framework_busy'],
          <String, Object?>{'transient_callbacks': 1});
      expect(json['extensions_busy'], <Map<String, Object?>>[
        <String, Object?>{
          'namespace': 'a',
          'reason': 'navigating',
          'est_ms': 100,
        },
        <String, Object?>{'namespace': 'b'},
      ]);
    });
  });
}
