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
  const List<String> stubNames = <String>['scripted-device.md', 'triage.md'];
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
      '| none (level 0) | Can a static check or hermetic Dart unit, widget, or '
          'golden test prove it? | Read `references/plain-dart-flutter.md` '
          'when a static check or hermetic Dart unit, widget, or golden test '
          'can prove it. |',
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
    final List<String> actualReferenceNames =
        Directory(referencesRoot)
            .listSync()
            .whereType<File>()
            .map((File file) => p.basename(file.path))
            .toList()
          ..sort();
    final List<String> expectedReferenceNames = referenceNames.toList()..sort();
    expect(actualReferenceNames, expectedReferenceNames);
    expect(skill.toLowerCase(), isNot(contains('see references/')));
  });

  test('the two pending references are exact one-line epic stubs', () {
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

  test('all seven complete gotchas stay verbatim in the entrypoint only', () {
    for (final String bullet in gotchaBullets) {
      expect(skill, contains(bullet), reason: bullet);
    }
    for (final String name in referenceNames.where(
      (String name) => !stubNames.contains(name),
    )) {
      final String contents = File(
        p.join(referencesRoot, name),
      ).readAsStringSync();
      for (final String bullet in gotchaBullets) {
        expect(contents, isNot(contains(bullet)), reason: '$name: $bullet');
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

  final String plainDartFlutterReference = File(
    p.join(referencesRoot, 'plain-dart-flutter.md'),
  ).readAsStringSync();
  final String widgetReference = File(
    p.join(referencesRoot, 'widget.md'),
  ).readAsStringSync();
  final String hardwareReference = File(
    p.join(referencesRoot, 'hardware.md'),
  ).readAsStringSync();
  final String oracleReference = File(
    p.join(referencesRoot, 'oracle.md'),
  ).readAsStringSync();

  test('level 0 pins five hermetic gates to falsifiers and receipts', () {
    for (final String label in <String>[
      'Proves:',
      'Command:',
      'Falsifier:',
      'Failure signature:',
      'Measured receipt:',
    ]) {
      expect(
        RegExp(
          '^\\*\\*$label\\*\\*',
          multiLine: true,
        ).allMatches(plainDartFlutterReference),
        hasLength(5),
        reason: label,
      );
    }
    for (final String command in <String>[
      '`dart analyze`',
      '`cd packages/leonard_contract && dart test '
          'test/strike_counter_test.dart`',
      '`cd packages/leonard_router && flutter test '
          'test/unit/observation/router_perception_test.dart`',
      '`cd packages/leonard_router && flutter test '
          'test/widget/extension/router_perception_equivalence_test.dart`',
      '`./tool/check_no_dart_io.sh`',
    ]) {
      expect(plainDartFlutterReference, contains(command), reason: command);
    }
    for (final String policy in <String>[
      'strict-casts',
      'strict-inference',
      'strict-raw-types',
      'prefer_single_quotes',
      'sort_pub_dependencies',
      'unawaited_futures',
      'avoid_print',
    ]) {
      expect(plainDartFlutterReference, contains(policy), reason: policy);
    }
    for (final String cite in <String>[
      'analysis_options.yaml:1-18',
      '.github/workflows/ci.yaml:18-24',
      'packages/leonard_contract/lib/src/strike_counter.dart:9',
      'packages/leonard_contract/lib/src/strike_counter.dart:11-18',
      'packages/leonard_contract/test/strike_counter_test.dart:5-31',
      'packages/leonard_router/lib/src/router_perception.dart:21-33',
      'packages/leonard_router/lib/src/router_perception.dart:42-49',
      'packages/leonard_router/test/unit/observation/'
          'router_perception_test.dart:9-52',
      'packages/leonard_router/test/widget/extension/'
          'router_perception_equivalence_test.dart:82-171',
      'tool/check_no_dart_io.sh:18-70',
      '.github/workflows/ci.yaml:22-24',
      'packages/leonard_agent/lib/src/vm_service_client.dart:10',
    ]) {
      expect(plainDartFlutterReference, contains(cite), reason: cite);
    }
    for (final String falsifier in <String>[
      "`int _consecutive = 'zero';`",
      '`void recordSuccess() => _consecutive++;`',
      '`RouteSnapshot? read() => _extension.readSnapshot();`',
      "`Field('currentRouteName', snap?.currentRouteName)`",
      "`import 'dart:io';`",
    ]) {
      expect(plainDartFlutterReference, contains(falsifier), reason: falsifier);
    }
    for (final String signature in <String>[
      'invalid_assignment',
      'Expected: false',
      'Actual: <true>',
      'snapshot becomes the exact router perception shape',
      'null `current_route_name` and `arguments` plus an empty `stack`',
      'missing `current_route_name` expectation',
      'golden JSON mismatch',
      'ERROR: packages/leonard_agent/lib must not import dart:io',
    ]) {
      expect(plainDartFlutterReference, contains(signature), reason: signature);
    }
    for (final String receipt in <String>[
      '2 issues found',
      'info-level `depend_on_referenced_packages` diagnostics',
      '+2: All tests passed!',
      '+5: All tests passed!',
      'OK: leonard_agent is Flutter-free; leonard_agent + leonard_devtools '
          'libs are dart:io-free; vm_service_io is confined to '
          'packages/leonard_agent/lib/src/vm_service_client_io.dart',
    ]) {
      expect(plainDartFlutterReference, contains(receipt), reason: receipt);
    }
    expect(
      RegExp(
        RegExp.escape(
          'On the 2026-09-08 base, the command reported '
          '`+2: All tests passed!`.',
        ),
      ).allMatches(plainDartFlutterReference),
      hasLength(2),
    );
  });

  test('level 0 keeps hermetic Leonard code below the live boundary', () {
    for (final String limitation in <String>[
      'real rendering on a device',
      'real gestures',
      'real platform channels',
      'anything requiring a live VM service',
    ]) {
      expect(
        plainDartFlutterReference,
        contains(limitation),
        reason: limitation,
      );
    }
    expect(plainDartFlutterReference, contains('package:integration_test'));
    for (final String boundary in <String>[
      'Testing Leonard packages or types hermetically stays at level 0; level '
          '0 does not launch or drive a running app with Leonard.',
      'Use `package:integration_test` as the level-0 exception when Flutter '
          'owns the integration run and Leonard is absent.',
      'The moment Leonard drives the running app, leave level 0 and follow the '
          'router;',
    ]) {
      expect(plainDartFlutterReference, contains(boundary), reason: boundary);
    }
    expect(
      plainDartFlutterReference,
      isNot(contains('Level 0 does not use lenny.')),
    );
    expect(
      plainDartFlutterReference,
      isNot(contains('The moment lenny participates')),
    );
    expect(
      plainDartFlutterReference,
      contains(
        'grid_assets/leonard_grid_assets/extension/station_overlay/claude/'
        'skills/test-with-leonard/SKILL.md:30',
      ),
    );
    expect(
      plainDartFlutterReference,
      isNot(contains('Content for this reference is not written yet')),
    );
    expect(plainDartFlutterReference, isNot(contains('/Users/')));
  });

  test(
    'level 1 pins one fake setup and one observation equivalence assertion',
    () {
      for (final String label in <String>[
        'Proves:',
        'Command:',
        'Falsifier:',
        'Failure signature:',
      ]) {
        expect(
          RegExp(
            '^\\*\\*$label\\*\\*',
            multiLine: true,
          ).allMatches(widgetReference),
          hasLength(2),
          reason: label,
        );
      }
      for (final String label in <String>['Setup:', 'Assertion:']) {
        expect(
          RegExp(
            '^\\*\\*$label\\*\\*',
            multiLine: true,
          ).allMatches(widgetReference),
          hasLength(1),
          reason: label,
        );
      }
      expect(
        RegExp(r'assertObservationEquivalent\(').allMatches(widgetReference),
        hasLength(1),
      );
      for (final String command in <String>[
        '`cd packages/leonard_flutter_test && flutter test '
            'test/binding_integration_test.dart`',
        '`cd packages/leonard_riverpod && flutter test '
            'test/unit/extension/riverpod_perception_equivalence_test.dart`',
      ]) {
        expect(widgetReference, contains(command), reason: command);
      }
      for (final String setup in <String>[
        "import 'package:leonard_flutter_test/leonard_flutter_test.dart';",
        'late LeonardBinding binding;',
        'late BindingVmServiceFake fake;',
        'binding = LeonardBinding.ensureInitialized(',
        'extensions: <LeonardExtension>[_SampleEchoExtension()],',
        'await Future<void>.delayed(Duration.zero);',
        'fake = BindingVmServiceFake(binding);',
        'await fake.dispose();',
      ]) {
        expect(widgetReference, contains(setup), reason: setup);
      }
      for (final String falsifier in <String>[
        "ToolResult(ok: true, value: 'wrong')",
        "'extensions': <String, Object?>{},",
      ]) {
        expect(widgetReference, contains(falsifier), reason: falsifier);
      }
      for (final String signature in <String>[
        "Expected: 'hello'",
        "Actual: 'wrong'",
        'extension "riverpod" fragment must match between legacy and '
            'perception paths',
      ]) {
        expect(widgetReference, contains(signature), reason: signature);
      }
      for (final String cite in <String>[
        'packages/leonard_flutter/example/diagnostic_fixture/test/'
            'diagnostic_fixture_test.dart:15-22',
        'packages/leonard_flutter/example/diagnostic_fixture/test/'
            'diagnostic_fixture_test.dart:44-68',
        'packages/leonard_flutter_test/lib/leonard_flutter_test.dart:1-5',
        'packages/leonard_flutter_test/lib/src/'
            'binding_vm_service_fake.dart:34-39',
        'packages/leonard_flutter_test/test/'
            'binding_integration_test.dart:120-149',
        'packages/leonard_flutter_test/test/'
            'binding_integration_test.dart:42-65',
        'packages/leonard_flutter_test/test/'
            'binding_integration_test.dart:38-39',
        'packages/leonard_flutter_test/lib/src/'
            'observation_equivalence.dart:5-37',
        'packages/leonard_riverpod/test/unit/extension/'
            'riverpod_perception_equivalence_test.dart:154-180',
        'packages/leonard_riverpod/test/unit/extension/'
            'riverpod_perception_equivalence_test.dart:178',
      ]) {
        expect(widgetReference, contains(cite), reason: cite);
      }
    },
  );

  test('level 1 names two false-negative console signatures', () {
    expect(
      RegExp(
        r'^### False negative \d+ —',
        multiLine: true,
      ).allMatches(widgetReference),
      hasLength(2),
    );
    for (final String signature in <String>[
      'Bad state: LeonardBinding cannot be installed: another WidgetsBinding '
          '(AutomatedTestWidgetsFlutterBinding) is already active.',
      'All tests passed!',
    ]) {
      expect(widgetReference, contains(signature), reason: signature);
    }
    for (final String evidence in <String>[
      'AutomatedTestWidgetsFlutterBinding',
      'IntegrationTestWidgetsFlutterBinding',
      'legacyExtensions.keys',
      'packages/leonard_flutter/lib/src/binding/'
          'leonard_binding.dart:180-187',
      'packages/leonard_flutter/lib/src/binding/leonard_binding.dart:185',
      'packages/leonard_flutter/test/unit/binding/'
          'binding_conflict_test.dart:6-22',
      'packages/leonard_flutter_test/lib/src/'
          'observation_equivalence.dart:24-37',
    ]) {
      expect(widgetReference, contains(evidence), reason: evidence);
    }
  });

  test('level 1 escalates live observables to scripted device', () {
    for (final String limitation in <String>[
      'real VM-service discovery or transport',
      'isolate selection',
      'engine-backed rendering',
      'real input',
      'platform channels',
      'device OS behavior',
      'level 2',
      'references/scripted-device.md',
      'simulator or emulator',
      'grid_assets/leonard_grid_assets/extension/station_overlay/claude/'
          'skills/test-with-leonard/SKILL.md:19',
    ]) {
      expect(widgetReference, contains(limitation), reason: limitation);
    }
    expect(
      widgetReference,
      isNot(contains('Content for this reference is not written yet')),
    );
    expect(widgetReference, isNot(contains('/Users/')));
  });

  test('level 3 delegates wired iOS dogfood to the canonical runbook', () {
    for (final String label in <String>[
      'Proves:',
      'Command:',
      'Falsifier:',
      'Failure signature:',
    ]) {
      expect(
        RegExp(
          '^\\*\\*$label\\*\\*',
          multiLine: true,
        ).allMatches(hardwareReference),
        hasLength(2),
        reason: label,
      );
    }
    for (final String cite in <String>[
      'docs/RUNBOOK-e2e-dogfood.md:17-41',
      'docs/RUNBOOK-e2e-dogfood.md:45-50',
      'docs/RUNBOOK-e2e-dogfood.md:52-67',
      'docs/RUNBOOK-e2e-dogfood.md:69-86',
      'docs/RUNBOOK-e2e-dogfood.md:88-102',
      'docs/RUNBOOK-e2e-dogfood.md:103-126',
      'docs/RUNBOOK-e2e-dogfood.md:128-145',
    ]) {
      expect(hardwareReference, contains(cite), reason: cite);
    }
    for (final String evidence in <String>[
      'wired iOS device',
      'iPad',
      'device attach',
      'iproxy` cleanup',
      'Detach the target before the device attach check',
      'target is absent from the device listing',
      'marked `(wireless)`',
      'no VM-service URI',
    ]) {
      expect(hardwareReference, contains(evidence), reason: evidence);
    }
    for (final String copiedCommand in <String>[
      'flutter run -d 00008110-001651523CE3801E',
      'source ~/.lenny-dogfood.env',
      'pkill -f "iproxy .* --udid',
    ]) {
      expect(
        hardwareReference,
        isNot(contains(copiedCommand)),
        reason: copiedCommand,
      );
    }
  });

  test('level 3 pins Android permission proof inputs and evidence', () {
    for (final String evidence in <String>[
      'cd packages/leonard_native && dart run '
          'tool/android_permission_dialog_proof.dart capture',
      'cd packages/leonard_native && dart run '
          'tool/android_permission_dialog_proof.dart verify',
      ':id/grant_dialog',
      'permission_allow_button',
      'permission_deny_button',
      'localized visible strings',
      'dismissal is refused with the dialog still visible',
      'allow closes and grants',
      'deny closes and does not grant',
      'Replace the captured `grant_dialog` resource id with an unrecognized id',
      'grant dialog absent after startup wait',
      'captured /source has no permission dialog',
      'live permission action proof failed',
      "const String serial = 'RF8RB21P6LN';",
      'no `--serial` argument',
      'local, uncommitted edit',
      'lenny-91vu',
      'HARDWARE_PROOF FAIL: Bad state: RF8RB21P6LN unavailable: '
          'lenny-91vu must be open',
    ]) {
      expect(hardwareReference, contains(evidence), reason: evidence);
    }
    for (final String cite in <String>[
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:705-732',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:219-240',
      'packages/leonard_native/test/fixtures/'
          'android_permission_dialog_source.xml:20-35',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:307-327',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:594-613',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:232-240',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:555-564',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:10',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:19-20',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:156-158',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:713-727',
      'packages/leonard_native/tool/'
          'android_permission_dialog_proof.dart:135-153',
    ]) {
      expect(hardwareReference, contains(cite), reason: cite);
    }
  });

  test('level 3 is manual and escalates independent judgment', () {
    for (final String boundary in <String>[
      'manual runbook',
      'no automated lane runs level 3',
      'simulator or emulator',
      'markTestSkipped',
      'human device pass',
      'independent verdict',
      'level 4',
      'references/oracle.md',
      'grid_assets/leonard_grid_assets/extension/station_overlay/claude/'
          'skills/test-with-leonard/SKILL.md:19-21',
      'grid_assets/leonard_grid_assets/extension/station_overlay/claude/'
          'skills/test-with-leonard/SKILL.md:32-34',
    ]) {
      expect(hardwareReference, contains(boundary), reason: boundary);
    }
    expect(
      hardwareReference,
      isNot(contains('Content for this reference is not written yet')),
    );
    expect(hardwareReference, isNot(contains('/Users/')));
  });

  test('level 4 pins two independent gauntlet verdicts', () {
    for (final String label in <String>[
      'Proves:',
      'Command:',
      'Falsifier:',
      'Failure signature:',
    ]) {
      expect(
        RegExp(
          '^\\*\\*$label\\*\\*',
          multiLine: true,
        ).allMatches(oracleReference),
        hasLength(2),
        reason: label,
      );
    }
    for (final String command in <String>[
      '`cd packages/leonard_flutter/example/sample_app && flutter test '
          'test/gauntlet/gauntlet_live_harness_test.dart --plain-name '
          "'settle/decorative-motion passes only when goal_reached is true'`",
      '`cd packages/leonard_flutter/example/sample_app && flutter test '
          'test/gauntlet/gauntlet_live_harness_test.dart --plain-name '
          "'answer verdict rejects a mismatched reported value'`",
    ]) {
      expect(oracleReference, contains(command), reason: command);
    }
    for (final String evidence in <String>[
      'GauntletLiveHarness',
      'GauntletDriver',
      'GauntletOracleReader',
      'reported',
      'goal_reached',
      'expected',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:7-11',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:70-97',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:100-107',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:100-164',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:120-148',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:130-134',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness.dart:151-163',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness_test.dart:67-97',
      'packages/leonard_flutter/example/sample_app/test/gauntlet/'
          'gauntlet_live_harness_test.dart:99-169',
      'Return `goal_reached: false` from the private reader after the driver '
          'finishes.',
      'Report `count: 9` while the private expected value is `count: 8`.',
      'Bad state: settle/decorative-motion: goal_reached is false',
      'Bad state: vision/count-spatial: answer mismatch for count',
    ]) {
      expect(oracleReference, contains(evidence), reason: evidence);
    }
  });

  test('level 4 keeps the oracle outside the driving observation', () {
    for (final String evidence in <String>[
      'ScenarioOracleState',
      'ext.gauntlet.oracle',
      'ext.flutter.exploration.*',
      'contributes no observation fragment',
      'driving agent',
      'observation bundle',
      'An observation leak invalidates the oracle.',
      'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
          'scenario_oracle.dart:6-13',
      'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
          'scenario_oracle.dart:15',
      'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
          'scenario_oracle.dart:23-55',
      'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
          'scenario_oracle.dart:65-103',
      'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
          'scenario_oracle.dart:79',
      'packages/leonard_flutter/example/sample_app/lib/main.dart:18-20',
    ]) {
      expect(oracleReference, contains(evidence), reason: evidence);
    }
  });

  test(
    'level 4 separates self-report from evidence and names its boundary',
    () {
      for (final String evidence in <String>[
        'SessionOutcome.done',
        'self-report',
        'an observation must prove the completion claim',
        'packages/leonard_agent/lib/src/loop_driver/loop_driver.dart:450',
        'packages/leonard_agent/lib/src/loop_driver/loop_driver.dart:482-489',
        'packages/leonard_agent/lib/src/loop_driver/types.dart:66-68',
        'docs/decisions/'
            '2026-09-01-a4-core-done-is-gated-by-a-scenario-declared-'
            'reason-form.md:21-33',
        'docs/decisions/'
            '2026-09-01-a5-core-done-is-additionally-gated-by-an-observed-'
            'evidence-p.md:21-37',
        'not worth',
        'cheapest level',
        'per-scenario app instrumentation',
        'running app and VM service',
        'separate grader maintenance',
        'uninstrumented or subjective goal',
        'stale or wrong ground truth',
        'packages/leonard_flutter/example/sample_app/lib/gauntlet/'
            'scenario_oracle.dart:105-167',
        'packages/leonard_flutter/example/sample_app/test/gauntlet/'
            'gauntlet_live_harness.dart:135-163',
      ]) {
        expect(oracleReference, contains(evidence), reason: evidence);
      }
      expect(
        oracleReference,
        isNot(contains('Content for this reference is not written yet')),
      );
      expect(oracleReference, isNot(contains('/Users/')));
    },
  );

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
