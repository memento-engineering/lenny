import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String repositoryRoot = p.normalize(
    p.join(Directory.current.path, '..', '..'),
  );
  final String skillRoot = p.join(
    repositoryRoot,
    'grid_assets',
    'leonard_grid_assets',
    'extension',
    'station_overlay',
    'claude',
    'skills',
    'test-with-leonard',
  );
  final File skillFile = File(p.join(skillRoot, 'SKILL.md'));
  final String skill = skillFile.readAsStringSync();
  final String referencesRoot = p.join(skillRoot, 'references');

  const String testFrontmatter = '''---
name: test-with-leonard
description: >
  Author tests and improve coverage for Dart and Flutter apps with Leonard. Use
  when asked to "write a test for my Flutter app", "add coverage with lenny",
  or "test this screen end to end". This skill owns test authoring and choosing
  the cheapest level that can prove the behaviour. Use the
  `drive-with-leonard` skill when asked to drive a running app toward a goal.
---
''';
  const String driveFrontmatter = '''---
name: drive-with-leonard
description: >
  Drive and verify a running program with an LLM via Leonard — observe its
  runtime state over the Dart VM service, act with tools, work toward a goal,
  and check the outcome. Use for requests such as "drive my app to do X" or
  otherwise exercise a running app or process toward a goal. This skill owns
  live driving, not test authoring. Use the `test-with-leonard` skill when asked
  to "write a test for my Flutter app", "add coverage with lenny", or "test this
  screen end to end".
---
''';
  const List<String> referenceNames = <String>[
    'plain-dart-flutter.md',
    'widget.md',
    'scripted-device.md',
    'hardware.md',
    'oracle.md',
    'triage.md',
    'mutation.md',
  ];
  const List<String> stubNames = <String>[
    'plain-dart-flutter.md',
    'widget.md',
    'scripted-device.md',
    'hardware.md',
    'oracle.md',
    'triage.md',
  ];
  const List<String> gotchaBullets = <String>[
    '* `SessionOutcome.done` is the MODEL calling `core.done`. It is a '
        'self-report, not an oracle. A test whose only assertion is '
        '`outcome == done` asserts that the model believed itself.',
    '* `ext.gauntlet.oracle` is registered DELIBERATELY outside '
        '`ext.flutter.exploration.*` and contributes no observation fragment, '
        'so the driving agent cannot read the answer out of its own bundle. '
        'That separation is the whole reason level 4 grades anything. An '
        'oracle that leaks into the observation is not an oracle.',
    '* `LeonardBinding` is a custom WidgetsBinding and THROWS on '
        'IntegrationTestWidgetsFlutterBinding '
        '(packages/leonard_flutter/lib/src/binding/leonard_binding.dart:185). '
        'You cannot drive an app under `package:integration_test`. PRD v0.5 '
        '§162.',
    "* lenny's `integration_test/` directories are a plain directory name "
        'run by `dart test`. NO pubspec in the repo depends on '
        '`package:integration_test`. The collision of names is the single '
        'most likely thing for a consumer to get wrong.',
    '* Every live tier calls `markTestSkipped` and exits 0 without its env '
        'vars. A lenny e2e suite can therefore NEVER be a station '
        'validation_plan — it passes vacuously. Say this where the agent will '
        'read it before wiring a gate.',
    '* `melos test` (the default gate) EXCLUDES the integration suites by '
        'design. They run only under `melos test:integration`.',
    '* The automated suites target simulator/emulator; hardware is the manual '
        'runbook. The intuition is backwards and consumers will assume the '
        'opposite.',
  ];
  const List<String> loadBearingTokens = <String>[
    'SessionOutcome.done',
    'ext.gauntlet.oracle',
    'LeonardBinding',
    'IntegrationTestWidgetsFlutterBinding',
    'integration_test/',
    'markTestSkipped',
    'melos test:integration',
    'hardware is the manual runbook',
  ];

  test(
    'the skill entrypoint has the exact frontmatter, sections, and budget',
    () {
      expect(skillFile.existsSync(), isTrue);
      expect(skill, startsWith(testFrontmatter));
      expect(
        RegExp(
          r'^#{1,6} .+$',
          multiLine: true,
        ).allMatches(skill).map((RegExpMatch match) => match.group(0)).toList(),
        <String>['## Routing', '## Gotchas'],
      );
      expect(skill.split('\n'), hasLength(lessThan(500)));
      expect(skillFile.lengthSync(), lessThan(20000));
      for (final String phrase in <String>[
        'write a test for my Flutter app',
        'add coverage with lenny',
        'test this screen end to end',
      ]) {
        expect(skill, contains(phrase), reason: phrase);
      }
      expect(skill, contains('This skill owns test authoring'));
      expect(skill, isNot(contains('drive my app to do X')));
      expect(
        skill,
        contains(
          '`drive-with-leonard` skill when asked to drive a running app toward '
          'a goal',
        ),
      );

      final String driveSkill = File(
        p.join(
          repositoryRoot,
          'packages',
          'leonard_cli',
          'lib',
          'assets',
          'skills',
          'drive-with-leonard',
          'SKILL.md',
        ),
      ).readAsStringSync();
      expect(driveSkill, startsWith(driveFrontmatter));
      expect(driveSkill, contains('live driving, not test authoring'));
      expect(driveSkill, contains('Use the `test-with-leonard` skill'));
    },
  );

  test('the router takes the cheapest proving level and names every load', () {
    var previousIndex = -1;
    for (final String label in <String>[
      'none (level 0)',
      'widget/unit',
      'scripted device',
      'hardware',
      'oracle-graded',
    ]) {
      final String marker = '| $label |';
      expect(RegExp(RegExp.escape(marker)).allMatches(skill), hasLength(1));
      final int index = skill.indexOf(marker);
      expect(index, greaterThan(previousIndex), reason: label);
      previousIndex = index;
    }

    for (final String row in <String>[
      '| none (level 0) | Can a widget test or golden prove it? | Read '
          '`references/plain-dart-flutter.md` when a widget test or golden can '
          'prove it. |',
      '| widget/unit | Does the test need no device because it covers an '
          'extension or observation? | Read `references/widget.md` when no '
          'device is required and the test covers an extension or '
          'observation. |',
      '| scripted device | Does the test need a real Flutter app on a '
          'simulator or emulator? | Read `references/scripted-device.md` when '
          'the test needs a real Flutter app on a simulator or emulator. |',
      '| hardware | Does the behaviour exist only on a physical device? | '
          'Read `references/hardware.md` when the behaviour exists only on a '
          'physical device. |',
      '| oracle-graded | Must the test judge whether the agent reached the '
          'goal? | Read `references/oracle.md` when the test must grade '
          'whether the agent reached the goal. |',
    ]) {
      expect(skill, contains(row), reason: row);
    }
    for (final String trigger in <String>[
      'Read `references/triage.md` when a run failed and the cause is unclear.',
      'Read `references/mutation.md` when the ask is coverage quality rather '
          'than a new test.',
    ]) {
      expect(skill, contains(trigger), reason: trigger);
    }

    final Set<String> mentionedReferences = RegExp(
      r'`references/([a-z-]+\.md)`',
    ).allMatches(skill).map((RegExpMatch match) => match.group(1)!).toSet();
    expect(mentionedReferences, referenceNames.toSet());
    for (final String name in mentionedReferences) {
      expect(File(p.join(referencesRoot, name)).existsSync(), isTrue);
    }
    expect(skill.toLowerCase(), isNot(contains('see references/')));
  });

  test('the six pending references are exact one-line epic stubs', () {
    const String stub =
        'Content for this reference is not written yet; tracked by epic '
        'lenny-kgvz.\n';
    for (final String name in stubNames) {
      final String contents = File(
        p.join(referencesRoot, name),
      ).readAsStringSync();
      expect(contents, stub, reason: name);
      expect(
        RegExp(
          r'\blenny-[a-z0-9.]+\b',
        ).allMatches(contents).map((RegExpMatch match) => match.group(0)),
        <String>['lenny-kgvz'],
        reason: name,
      );
      for (final String token in loadBearingTokens) {
        expect(contents, isNot(contains(token)), reason: '$name: $token');
      }
    }
  });

  test('all seven complete gotchas stay in the entrypoint only', () {
    for (final String bullet in gotchaBullets) {
      expect(skill, contains(bullet), reason: bullet);
    }
    for (final String name in referenceNames) {
      final String contents = File(
        p.join(referencesRoot, name),
      ).readAsStringSync();
      for (final String token in loadBearingTokens) {
        expect(contents, isNot(contains(token)), reason: '$name: $token');
      }
    }
  });

  test('the suite is standalone and the retired sources are absent', () {
    final String suite = File(
      p.join(
        repositoryRoot,
        'grid_assets',
        'leonard_grid_assets',
        'test',
        'test_with_leonard_skill_test.dart',
      ),
    ).readAsStringSync();
    expect(
      RegExp(
        r'^import .+;$',
        multiLine: true,
      ).allMatches(suite).map((RegExpMatch match) => match.group(0)).toList(),
      <String>[
        "import 'dart:io';",
        "import 'package:path/path.dart' as p;",
        "import 'package:test/test.dart';",
      ],
    );
    expect(
      Directory(
        p.join(
          repositoryRoot,
          'packages',
          'leonard_cli',
          'lib',
          'assets',
          'skills',
          'test-with-leonard',
        ),
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(
          repositoryRoot,
          'packages',
          'leonard_cli',
          'test',
          'assets',
          'mutation_reference_test.dart',
        ),
      ).existsSync(),
      isFalse,
    );
  });

  final String reference = File(
    p.join(referencesRoot, 'mutation.md'),
  ).readAsStringSync();

  test('starts every assertion review with a named breaking change', () {
    expect(
      reference,
      contains(
        'Before writing an assertion, name the single-line source change '
        'that would make the test fail.',
      ),
    );
    expect(reference, contains('the assertion is decorative'));
    expect(reference, contains('could a wrong output still produce'));
  });

  test('carries every calibrated failure mode and its Leonard evidence', () {
    for (final String evidence in <String>[
      'Contract-facing text is behaviour',
      'Protocol constants are behaviour',
      'A shipped test double is public API',
      'Probe asymmetry',
      '`throwsX` proves a throw type, not a diagnosis',
      'validator and coercer branch',
      'Drive testability seams',
      'class documentation as a test checklist',
      'consumer is tolerant',
      'lenny-i2j6',
      'lenny-tkr2',
      'lenny-s4mb',
    ]) {
      expect(reference, contains(evidence), reason: evidence);
    }
  });

  test('requires evidence before exclusions and before bug-fix claims', () {
    expect(reference, contains('Verify before excluding'));
    expect(reference, contains('Essential equivalence'));
    expect(reference, contains('Incidental equivalence'));
    expect(reference, contains('Read results per file'));
    expect(
      reference,
      contains('fails on the parent commit and passes on the fix'),
    );
  });

  test('reports measured calibration, including contradiction and uplift', () {
    for (final String receipt in <String>[
      '542 mutants, 215 survivors, 60.33% killed',
      '49.09% killed',
      '54/55 killed, 98.18%',
      '126 of 777 mutants',
      '77.78%',
      'Three of five predictions were wrong',
      '13/13',
      '8/8',
      '5/5',
    ]) {
      expect(reference, contains(receipt), reason: receipt);
    }
  });
}
