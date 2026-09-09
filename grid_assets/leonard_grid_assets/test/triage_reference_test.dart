import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the routed triage reference is structured and failure-code-first', () {
    final File reference = File(
      'extension/station_overlay/claude/skills/'
      'test-with-leonard/references/triage.md',
    );
    expect(reference.existsSync(), true);
    final String text = reference.readAsStringSync();
    for (final String field in <String>[
      'status',
      'failure_codes',
      'driver_exit_status',
      'trajectory_path',
      'provider_request_id',
      'model',
      'expectation_evidence',
    ]) {
      expect(text, contains('`$field`'), reason: field);
    }
    for (final String classification in <String>[
      'Model behaviour',
      'Goal under-specification',
      'Harness or setup',
      'harness/extension defect',
    ]) {
      expect(text, contains(classification), reason: classification);
    }
    expect(text, contains('debug-inference'));
    expect(text, contains('when it is present'));
    expect(text, contains('When it is absent'));
    expect(text, contains('never infer PASS or FAIL from child stdout'));
    expect(text, contains('one bead for each distinct defect'));
  });

  test('triage is authored only in the routed overlay reference', () {
    for (final String forbiddenPath in <String>[
      'extension/station_overlay/claude/skills/triage/SKILL.md',
      '../../packages/leonard_cli/lib/assets/skills/test-with-leonard',
      '../../packages/leonard_grid_assets',
    ]) {
      expect(
        FileSystemEntity.typeSync(forbiddenPath),
        FileSystemEntityType.notFound,
      );
    }
  });
}
