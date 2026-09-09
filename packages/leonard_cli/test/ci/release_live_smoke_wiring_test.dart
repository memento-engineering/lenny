import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final Directory workspace = _workspaceRoot();
  final String publishWorkflow = File(
    p.join(workspace.path, '.github', 'workflows', 'publish.yml'),
  ).readAsStringSync();
  final String prWorkflow = File(
    p.join(workspace.path, '.github', 'workflows', 'ci.yaml'),
  ).readAsStringSync();

  test('flutter release tags require the live macOS capability smoke', () {
    final String live = _jobBlock(publishWorkflow, 'live-flutter-macos');
    expect(live, contains('needs: parse'));
    expect(
      live,
      contains("if: needs.parse.outputs.package == 'leonard_flutter'"),
    );
    expect(live, contains('runs-on: macos-14'));
    expect(live, contains('timeout-minutes: 15'));
    expect(live, contains("flutter-version: '3.41.4'"));
    expect(live, contains('channel: stable'));
    expect(live, contains('- run: flutter pub get'));
    expect(
      live,
      contains('- run: dart run melos run test:live:macos --no-select'),
    );

    final String gate = _jobBlock(publishWorkflow, 'release-gate');
    expect(gate, contains('needs: [parse, live-flutter-macos]'));
    expect(gate, contains('if: always()'));
    expect(gate, contains('runs-on: ubuntu-latest'));
    expect(gate, contains(r'test "$PARSE_RESULT" = success'));
    expect(gate, contains(r'if [ "$PACKAGE" = leonard_flutter ]; then'));
    expect(gate, contains(r'test "$LIVE_RESULT" = success'));
    expect(gate, contains(r'test "$LIVE_RESULT" = skipped'));

    final String publish = _jobBlock(publishWorkflow, 'publish');
    final String publishDevTools = _jobBlock(
      publishWorkflow,
      'publish-leonard-devtools',
    );
    expect(publish, contains('needs: [parse, release-gate]'));
    expect(publishDevTools, contains('needs: [parse, release-gate]'));
    expect(prWorkflow, isNot(contains('test:live:macos')));
  });
}

Directory _workspaceRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    if (File(
          p.join(directory.path, '.github', 'workflows', 'publish.yml'),
        ).existsSync() &&
        File(
          p.join(directory.path, 'packages', 'leonard_cli', 'pubspec.yaml'),
        ).existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError(
    'cannot locate the lenny workspace from ${Directory.current}',
  );
}

String _jobBlock(String workflow, String jobName) {
  final String marker = '\n  $jobName:\n';
  final int markerIndex = workflow.indexOf(marker);
  if (markerIndex < 0) {
    throw StateError('workflow has no top-level $jobName job');
  }
  final int start = markerIndex + 1;
  final RegExp nextJob = RegExp(r'^  [A-Za-z0-9_-]+:\s*$', multiLine: true);
  final RegExpMatch? endMatch = nextJob.firstMatch(
    workflow.substring(start + marker.length - 1),
  );
  final int end = endMatch == null
      ? workflow.length
      : start + marker.length - 1 + endMatch.start;
  return workflow.substring(start, end);
}
