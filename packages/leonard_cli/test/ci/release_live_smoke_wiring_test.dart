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

  test(
    'flutter release tags require the live macOS capability smoke',
    () async {
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

      final String liveCondition = _jobIfExpression(live);
      final String publishCondition = _jobIfExpression(publish);
      final String publishDevToolsCondition = _jobIfExpression(publishDevTools);
      final String gateScript = _jobRunScript(gate);
      const List<
        ({
          String package,
          bool runLive,
          bool runPublish,
          bool runPublishDevTools,
          String liveResult,
        })
      >
      packageMatrix =
          <
            ({
              String package,
              bool runLive,
              bool runPublish,
              bool runPublishDevTools,
              String liveResult,
            })
          >[
            (
              package: 'leonard_flutter',
              runLive: true,
              runPublish: true,
              runPublishDevTools: false,
              liveResult: 'success',
            ),
            (
              package: 'leonard_agent',
              runLive: false,
              runPublish: true,
              runPublishDevTools: false,
              liveResult: 'skipped',
            ),
            (
              package: 'leonard_cli',
              runLive: false,
              runPublish: true,
              runPublishDevTools: false,
              liveResult: 'skipped',
            ),
          ];

      for (final row in packageMatrix) {
        expect(
          _evaluatePackageCondition(liveCondition, row.package),
          row.runLive,
          reason: '${row.package} live job',
        );
        expect(
          _evaluatePackageCondition(publishCondition, row.package),
          row.runPublish,
          reason: '${row.package} pub.dev publisher',
        );
        expect(
          _evaluatePackageCondition(publishDevToolsCondition, row.package),
          row.runPublishDevTools,
          reason: '${row.package} DevTools publisher',
        );

        final ProcessResult acceptedGate = await Process.run(
          'bash',
          <String>['-ceu', gateScript],
          environment: <String, String>{
            'PACKAGE': row.package,
            'PARSE_RESULT': 'success',
            'LIVE_RESULT': row.liveResult,
          },
        );
        expect(
          acceptedGate.exitCode,
          0,
          reason: '${row.package} expected gate result: ${acceptedGate.stderr}',
        );

        final String oppositeLiveResult = row.liveResult == 'success'
            ? 'skipped'
            : 'success';
        final ProcessResult rejectedGate = await Process.run(
          'bash',
          <String>['-ceu', gateScript],
          environment: <String, String>{
            'PACKAGE': row.package,
            'PARSE_RESULT': 'success',
            'LIVE_RESULT': oppositeLiveResult,
          },
        );
        expect(
          rejectedGate.exitCode,
          isNot(0),
          reason: '${row.package} accepted $oppositeLiveResult unexpectedly',
        );
      }

      expect(prWorkflow, isNot(contains('test:live:macos')));
    },
  );
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

String _jobIfExpression(String job) {
  final List<RegExpMatch> matches = RegExp(
    r'^    if: (.+)$',
    multiLine: true,
  ).allMatches(job).toList();
  if (matches.length != 1) {
    throw StateError('expected one top-level job if expression, got $matches');
  }
  return matches.single.group(1)!;
}

bool _evaluatePackageCondition(String expression, String package) {
  final RegExpMatch? match = RegExp(
    r"^needs\.parse\.outputs\.package (==|!=) '([^']+)'$",
  ).firstMatch(expression);
  if (match == null) {
    throw UnsupportedError('unsupported package condition: $expression');
  }
  final bool equals = package == match.group(2);
  return match.group(1) == '==' ? equals : !equals;
}

String _jobRunScript(String job) {
  final List<String> lines = job.split('\n');
  final List<int> runLines = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index] == '        run: |') index,
  ];
  if (runLines.length != 1) {
    throw StateError('expected one top-level run block, got $runLines');
  }

  final List<String> script = <String>[];
  for (var index = runLines.single + 1; index < lines.length; index++) {
    final String line = lines[index];
    if (line.isEmpty) {
      script.add(line);
      continue;
    }
    if (!line.startsWith('          ')) break;
    script.add(line.substring(10));
  }
  while (script.isNotEmpty && script.last.isEmpty) {
    script.removeLast();
  }
  if (script.isEmpty) {
    throw StateError('run block has no script body');
  }
  return script.join('\n');
}
