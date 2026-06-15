/// Drift guard for lenny-wisp-0go2a.4: the CLI's human-editable
/// `templates/AGENTS.md` and the web-bundled `kDefaultAgentsMd` const (used
/// by the DevTools panel, which can't read files) must stay in sync, so the
/// CLI and DevTools agents share one operating guide. Compared modulo
/// trailing whitespace so an editor's final-newline choice doesn't flap.
library;

import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('templates/AGENTS.md matches kDefaultAgentsMd', () {
    final file = File(p.join(_findPackageRoot(), 'templates', 'AGENTS.md'));
    expect(
      file.existsSync(),
      isTrue,
      reason: 'bundled AGENTS.md template should exist',
    );
    expect(
      file.readAsStringSync().trimRight(),
      equals(kDefaultAgentsMd.trimRight()),
      reason:
          'CLI template and web const have drifted — update one to match '
          'the other (see default_agents_md.dart).',
    );
  });
}

String _findPackageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: leonard_cli')) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return p.normalize(
    p.join(Directory.current.path, 'packages', 'leonard_cli'),
  );
}
