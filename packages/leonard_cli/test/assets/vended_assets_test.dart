/// Regression pins over the VENDED consumer assets (lenny-ev1g). These are
/// instructions an agent acts on and cannot check, shipped through two
/// channels (`leonard_cli:install` + the Claude Code marketplace) — so every
/// stale claim is wrong twice. Before this suite, `test/` had no coverage
/// over `lib/assets` at all and an asset-only change passed vacuously.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/vended_assets.dart';

void main() {
  final Map<String, String> assets = vendedMarkdown();

  test('the vended surface is non-empty and carries the collapsed agent', () {
    expect(assets, isNotEmpty);
    final Iterable<String> agents = assets.keys.where(
      (String p) => p.contains('/agents/'),
    );
    expect(
      agents.map((String p) => p.split('/').last).toList(),
      <String>['leonard-drive.agent.md'],
      reason:
          'exactly ONE drive agent ships — driver/pilot collapsed '
          '(lenny-ev1g); a second agent file here means the collapse '
          'regressed or the marketplace manifest needs updating',
    );
  });

  test('every outcome value named in any asset is a real wire value', () {
    for (final MapEntry<String, String> e in assets.entries) {
      for (final String token in outcomeTokensIn(e.value)) {
        expect(
          kSessionOutcomeWireValues,
          contains(token),
          reason:
              '${e.key} names outcome "$token", which SessionFooter '
              'never emits — an agent following it silently mis-reads runs '
              '(the 0.3.0-era agent_stuck defect)',
        );
      }
    }
  });

  test('every skill cross-referenced from an asset resolves on disk', () {
    for (final MapEntry<String, String> e in assets.entries) {
      for (final String name in skillReferencesIn(e.value)) {
        expect(
          skillExists(name),
          isTrue,
          reason:
              '${e.key} references "the `$name` skill" but '
              'assets/skills/$name/SKILL.md does not exist (the '
              'drive-flutter-app defect: a name that resolves nowhere)',
        );
      }
    }
  });

  test('the retired pure-Dart-host language is gone', () {
    for (final MapEntry<String, String> e in assets.entries) {
      for (final String retired in const <String>[
        'is the next piece',
        "Don't assume `dart run leonard_cli",
        'drive-flutter-app',
      ]) {
        expect(
          e.value.contains(retired),
          isFalse,
          reason:
              '${e.key} still carries the retired claim "$retired" — '
              'the pure-Dart host (leonard_host) ships today and the skill '
              'is named drive-with-leonard',
        );
      }
    }
  });

  test('the tool reference lives in the skill, not an agent', () {
    final String skill = assets.entries
        .firstWhere(
          (MapEntry<String, String> e) =>
              e.key.endsWith('drive-with-leonard/SKILL.md'),
        )
        .value;
    // The load-bearing reference lines moved from the pilot agent.
    expect(skill, contains('core.tap {node_id}'));
    expect(skill, contains('Never repeat an action that just failed'));
    expect(skill, contains('max - pos'));
    final String agent = assets.entries
        .firstWhere(
          (MapEntry<String, String> e) =>
              e.key.endsWith('leonard-drive.agent.md'),
        )
        .value;
    expect(
      agent.contains('core.long_press'),
      isFalse,
      reason:
          'the full tool table is reference material and lives in the '
          'skill; the agent points at it instead of carrying a copy that '
          'will drift',
    );
  });

  test('the vended install channel still sees the assets root', () {
    // The install entrypoint globs this directory; a rename that orphans it
    // ships an installer that installs nothing.
    expect(Directory('${vendedAssetsDir().path}/agents').existsSync(), isTrue);
    expect(Directory('${vendedAssetsDir().path}/skills').existsSync(), isTrue);
  });
}
