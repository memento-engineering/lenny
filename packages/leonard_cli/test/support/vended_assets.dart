/// Shared loader + assertion helpers over the VENDED consumer assets
/// (`lib/assets/`) — the surface that ships through both `leonard_cli:install`
/// and the Claude Code marketplace. Written for `vended_assets_test.dart` and
/// reusable by any suite that vends or scripts against these files
/// (lenny-kgvz.1's scripted-device level imports from here — one helper, not
/// two).
///
/// Everything here reads the REAL files from disk: an asset-only change must
/// not pass `dart test` vacuously.
library;

import 'dart:io';

/// The wire values `SessionFooter.toJson` actually emits for
/// `footer.outcome` (leonard_agent `trajectory/records.dart`). An asset that
/// names any other outcome teaches its reader to grep for a value the writer
/// never writes.
const Set<String> kSessionOutcomeWireValues = <String>{
  'done',
  'budget_exhausted',
  'harness_error',
};

/// Resolves `lib/assets` from either invocation cwd (package root or repo
/// root), mirroring the fixture resolvers in the other suites.
Directory vendedAssetsDir() {
  for (final String p in <String>[
    'lib/assets',
    'packages/leonard_cli/lib/assets',
  ]) {
    final Directory d = Directory(p);
    if (d.existsSync()) return d;
  }
  throw StateError('lib/assets not found from ${Directory.current.path}');
}

/// All vended markdown assets (agents + skills), path -> contents.
Map<String, String> vendedMarkdown() {
  final Directory root = vendedAssetsDir();
  final Map<String, String> out = <String, String>{};
  for (final FileSystemEntity e in root.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.md')) {
      out[e.path] = e.readAsStringSync();
    }
  }
  return out;
}

/// Every `"outcome":"x"` / `outcome == x` / bare `` `x` `` outcome mention in
/// [text] that looks like a trajectory outcome. Conservative on purpose: it
/// scans for the known-bad and known-good tokens rather than parsing prose.
Iterable<String> outcomeTokensIn(String text) sync* {
  // The full historical vocabulary — real values plus every retired/invented
  // one that has appeared in an asset. Extend when a new invention is caught.
  const Set<String> candidates = <String>{
    'done',
    'budget_exhausted',
    'harness_error',
    'agent_stuck',
    'budgetExhausted',
    'harnessError',
  };
  for (final String c in candidates) {
    if (RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(c)}(?![A-Za-z0-9_])',
    ).hasMatch(text)) {
      yield c;
    }
  }
}

/// Skill names cross-referenced from an asset (``the `<name>` skill``).
Iterable<String> skillReferencesIn(String text) sync* {
  for (final RegExpMatch m in RegExp(
    'the `([a-z0-9-]+)` skill',
  ).allMatches(text)) {
    yield m.group(1)!;
  }
}

/// Whether `assets/skills/<name>/SKILL.md` exists.
bool skillExists(String name) =>
    File('${vendedAssetsDir().path}/skills/$name/SKILL.md').existsSync();
