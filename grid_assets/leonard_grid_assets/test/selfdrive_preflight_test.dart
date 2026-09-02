import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

const String _model = 'qwen3.6-35b-a3b-8bit';

Bead _bead({String outer = _model, String inner = _model}) => Bead(
  id: 'lenny-selfdrive',
  metadata: <String, dynamic>{
    kSelfdriveScenarioKey:
        'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
    kSelfdriveOuterModelKey: outer,
    kSelfdriveInnerModelKey: inner,
  },
);

void main() {
  group('judgeSelfdriveModels', () {
    test('refuses a mismatch and names both ids', () {
      final PreflightVerdict verdict = judgeSelfdriveModels(
        outerModelId: 'outer-model',
        innerModelId: 'inner-model',
        servedModelIds: const <String>{'outer-model', 'inner-model'},
      );
      expect(verdict, isA<PreflightRefused>());
      final String message = (verdict as PreflightRefused).message;
      expect(message, contains('outer-model'));
      expect(message, contains('inner-model'));
    });

    test('refuses an absent outer id and names both slots', () {
      final PreflightVerdict verdict = judgeSelfdriveModels(
        outerModelId: ' ',
        innerModelId: 'inner-model',
        servedModelIds: const <String>{'inner-model'},
      );
      final String message = (verdict as PreflightRefused).message;
      expect(message, contains('outer=absent'));
      expect(message, contains('inner=inner-model'));
    });

    test('refuses an unserved equal id with a sorted catalog', () {
      final PreflightVerdict verdict = judgeSelfdriveModels(
        outerModelId: _model,
        innerModelId: _model,
        servedModelIds: const <String>{'z-model', 'a-model'},
      );
      final String message = (verdict as PreflightRefused).message;
      expect(message, contains(_model));
      expect(message, contains('served: a-model,z-model'));
    });

    test('clears an equal served id', () {
      final PreflightVerdict verdict = judgeSelfdriveModels(
        outerModelId: _model,
        innerModelId: _model,
        servedModelIds: const <String>{_model},
      );
      expect(verdict, isA<PreflightCleared>());
      expect((verdict as PreflightCleared).modelId, _model);
    });
  });

  group('SelfdrivePreflightCapability', () {
    SelfdrivePreflightCapability capabilityFor({
      required Map<String, String> environment,
    }) => SelfdrivePreflightCapability(
      models: (Uri base, String token) async {
        expect(base, Uri.parse('http://swift.example'));
        expect(token, 'token');
        return const <String>{_model};
      },
      env: (String name) => environment[name],
    );

    test('publishes the one matched model id', () async {
      final FakeTreeContext context = FakeTreeContext(
        values: <Type, Object>{Bead: _bead()},
      );
      final StepOutcome outcome = await capabilityFor(
        environment: const <String, String>{
          'SWIFT_INFER_ENDPOINT': 'http://swift.example',
          'SWIFT_INFER_AGENT_TOKEN': 'token',
        },
      ).run(context, stepArgs('lenny-selfdrive/preflight'));
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, <String, String>{
        kSelfdriveClearedModelKey: _model,
      });
    });

    test('refuses a mismatched bead', () async {
      final FakeTreeContext context = FakeTreeContext(
        values: <Type, Object>{
          Bead: _bead(outer: 'outer-model', inner: 'inner-model'),
        },
      );
      final SelfdrivePreflightCapability capability =
          SelfdrivePreflightCapability(
            models: (Uri _, String __) async => const <String>{
              'outer-model',
              'inner-model',
            },
            env: (String name) => const <String, String>{
              'SWIFT_INFER_ENDPOINT': 'http://swift.example',
            }[name],
          );
      final StepOutcome outcome = await capability.run(
        context,
        stepArgs('lenny-selfdrive/preflight'),
      );
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).reason, contains('outer-model'));
      expect(outcome.reason, contains('inner-model'));
    });

    test(
      'refuses an unset gateway endpoint without reading the catalog',
      () async {
        var called = false;
        final SelfdrivePreflightCapability capability =
            SelfdrivePreflightCapability(
              models: (Uri _, String __) async {
                called = true;
                return const <String>{_model};
              },
              env: (_) => null,
            );
        final StepOutcome outcome = await capability.run(
          FakeTreeContext(values: <Type, Object>{Bead: _bead()}),
          stepArgs('lenny-selfdrive/preflight'),
        );
        expect(outcome, isA<Failed>());
        expect((outcome as Failed).reason, contains('SWIFT_INFER_ENDPOINT'));
        expect(called, isFalse);
      },
    );
  });
}
