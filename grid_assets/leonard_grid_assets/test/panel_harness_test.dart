import 'dart:async';
import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const List<String> _uriLines = <String>[
  'SAMPLE_APP_VM_URI=ws://sample',
  'DTD_URI=ws://dtd',
  'PANEL_URL=http://panel',
  'PANEL_DWDS_URI=ws://panel',
];

void main() {
  group('SelfdriveUriLedger', () {
    test('becomes ready only after all four URI publications', () {
      final SelfdriveUriLedger ledger = SelfdriveUriLedger();
      for (final String line in _uriLines.take(3)) {
        ledger.absorb(line);
      }
      expect(ledger.isReady, isFalse);
      expect(ledger.missing, <String>['PANEL_DWDS_URI']);

      ledger.absorb(_uriLines.last);
      expect(ledger.isReady, isTrue);
      expect(ledger.published, <String, String>{
        'SAMPLE_APP_VM_URI': 'ws://sample',
        'DTD_URI': 'ws://dtd',
        'PANEL_URL': 'http://panel',
        'PANEL_DWDS_URI': 'ws://panel',
      });
    });

    test('ignores noise, bare lines, and empty known values', () {
      final SelfdriveUriLedger ledger = SelfdriveUriLedger()
        ..absorb('NOISE=x')
        ..absorb('hello')
        ..absorb('DTD_URI=');
      expect(ledger.published, isEmpty);
      expect(ledger.missing, kSelfdriveUriKeys);
    });
  });

  group('PanelHarnessCapability.dispatchOn', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('panel-harness-test.');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('publishes four URIs and the run directory', () async {
      final StreamController<String> diagnostics = StreamController<String>();
      final Completer<int> exit = Completer<int>();
      final PanelHarnessLease lease = PanelHarnessLease(
        process: HarnessProcess(
          diagnostics: diagnostics.stream,
          exitCode: exit.future,
          kill: () async {},
        ),
        runDir: temp.path,
      );
      final Future<StepOutcome> pending = const PanelHarnessCapability()
          .dispatchOn(
            lease,
            FakeTreeContext(),
            stepArgs('work/selfdrive/panel-harness'),
          );
      await Future<void>.delayed(Duration.zero);
      diagnostics.add('booting panel');
      for (final String line in _uriLines) {
        diagnostics.add(line);
      }

      final StepOutcome outcome = await pending;
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, <String, String>{
        'SAMPLE_APP_VM_URI': 'ws://sample',
        'DTD_URI': 'ws://dtd',
        'PANEL_URL': 'http://panel',
        'PANEL_DWDS_URI': 'ws://panel',
        kSelfdriveRunDirKey: temp.path,
      });
      expect(
        File(p.join(temp.path, 'harness.log')).readAsStringSync(),
        'booting panel\n${_uriLines.join('\n')}\n',
      );
      await diagnostics.close();
    });

    test('fails with the missing key when the harness exits early', () async {
      final StreamController<String> diagnostics = StreamController<String>();
      final Completer<int> exit = Completer<int>();
      final Future<StepOutcome> pending = const PanelHarnessCapability()
          .dispatchOn(
            PanelHarnessLease(
              process: HarnessProcess(
                diagnostics: diagnostics.stream,
                exitCode: exit.future,
                kill: () async {},
              ),
              runDir: temp.path,
            ),
            FakeTreeContext(),
            stepArgs('work/selfdrive/panel-harness'),
          );
      await Future<void>.delayed(Duration.zero);
      for (final String line in _uriLines.take(3)) {
        diagnostics.add(line);
      }
      await Future<void>.delayed(Duration.zero);
      exit.complete(1);

      final StepOutcome outcome = await pending;
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).reason, contains('PANEL_DWDS_URI'));
      await diagnostics.close();
    });

    test('fails with the missing key when readiness times out', () async {
      final StreamController<String> diagnostics = StreamController<String>();
      final Completer<int> exit = Completer<int>();
      final Future<StepOutcome> pending =
          PanelHarnessCapability(
            readyTimeout: const Duration(milliseconds: 50),
          ).dispatchOn(
            PanelHarnessLease(
              process: HarnessProcess(
                diagnostics: diagnostics.stream,
                exitCode: exit.future,
                kill: () async {},
              ),
              runDir: temp.path,
            ),
            FakeTreeContext(),
            stepArgs('work/selfdrive/panel-harness'),
          );
      await Future<void>.delayed(Duration.zero);
      for (final String line in _uriLines.take(3)) {
        diagnostics.add(line);
      }

      final StepOutcome outcome = await pending;
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).reason, contains('PANEL_DWDS_URI'));
      await diagnostics.close();
    });
  });
}
