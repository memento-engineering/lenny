/// Thin argv and JSON adapter over [E2eService].
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'e2e_sample_suite.dart';
import 'e2e_service.dart';
import 'e2e_session.dart';

/// `e2e` — run one generic session or the private sample suite.
class E2eCommand extends Command<int> {
  /// Creates the thin adapter over an injectable service and output sinks.
  E2eCommand({E2eService? service, StringSink? out, StringSink? err})
    : _service = service ?? const E2eService(SystemE2eRuntime()),
      _out = out ?? stdout,
      _err = err ?? stderr {
    argParser
      ..addOption('goal', help: 'Goal for one generic Leonard session.')
      ..addOption(
        'app-dir',
        help: 'Absolute Flutter app directory; overrides the sample app.',
      )
      ..addOption('model', defaultsTo: 'claude')
      ..addOption('model-id')
      ..addOption('device')
      ..addOption('extensions', defaultsTo: 'router,riverpod,dio')
      ..addOption('cli', defaultsTo: 'dart run leonard_cli')
      ..addOption('done-reason-pattern')
      ..addOption('done-evidence-pattern')
      ..addOption('expect-route')
      ..addOption('expect-label')
      ..addOption('expect-state')
      ..addOption(
        'sample-scenario',
        help: 'Run one named scenario from the sample suite.',
      )
      ..addFlag('sample-suite', negatable: false);
  }

  final E2eService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'e2e';

  @override
  final String description =
      'Run deterministic Leonard live-device E2E orchestration.';

  @override
  Future<int> run() async {
    final arguments = argResults!;
    final String goal = arguments.option('goal')?.trim() ?? '';
    final bool sampleSuite = arguments.flag('sample-suite');
    final bool hasSampleScenario = arguments.wasParsed('sample-scenario');
    if (hasSampleScenario && !sampleSuite) {
      return _refuse('--sample-scenario requires --sample-suite');
    }
    if (goal.isNotEmpty == sampleSuite) {
      return _refuse(
        'exactly one of a non-empty --goal or --sample-suite is required',
      );
    }
    List<E2eScenario> scenarios = kLeonardSampleSuite;
    if (hasSampleScenario) {
      final String scenarioName =
          arguments.option('sample-scenario')?.trim() ?? '';
      final List<E2eScenario> matches = kLeonardSampleSuite
          .where((E2eScenario scenario) => scenario.name == scenarioName)
          .toList(growable: false);
      if (matches.length != 1) {
        return _refuse(
          '--sample-scenario must be login, navigation, state_change, or scroll',
        );
      }
      scenarios = <E2eScenario>[matches.single];
    }

    final E2eModel? model = E2eModel.tryParse(
      arguments.option('model')?.trim() ?? '',
    );
    if (model == null) {
      return _refuse('--model must be claude, qwen-mlx, or openai');
    }
    final String? label = _optional(arguments.option('expect-label'));
    final String? state = _optional(arguments.option('expect-state'));
    if ((label == null) != (state == null)) {
      return _refuse(
        '--expect-label and --expect-state must be supplied together',
      );
    }
    final List<String> extensions = (arguments.option('extensions') ?? '')
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    if (extensions.isEmpty) return _refuse('--extensions must not be empty');
    final List<String> cliPrefix;
    try {
      cliPrefix = parseE2eCliPrefix(arguments.option('cli') ?? '');
    } on FormatException catch (error) {
      return _refuse(error.message);
    }
    if (cliPrefix.isEmpty) return _refuse('--cli must not be empty');

    String? appDir = _optional(arguments.option('app-dir'));
    if (!sampleSuite) {
      if (appDir == null || !p.isAbsolute(appDir)) {
        return _refuse('generic mode requires an absolute --app-dir');
      }
    } else if (appDir == null) {
      appDir = await findLeonardSampleAppDir(_service.runtime);
      if (appDir == null) {
        return _refuse(
          'could not find $kLeonardSampleAppDir beneath any ancestor',
        );
      }
    } else if (!p.isAbsolute(appDir)) {
      appDir = p.normalize(p.join(_service.runtime.currentDirectory, appDir));
    }

    final String? modelId = _optional(arguments.option('model-id'));
    final String? device = _optional(arguments.option('device'));
    if (sampleSuite) {
      final E2eSuiteVerdict verdict = await _service.runSampleSuite(
        appDir: appDir,
        model: model,
        modelId: modelId,
        device: device,
        extensions: extensions,
        cliPrefix: cliPrefix,
        scenarios: scenarios,
      );
      _out.writeln(jsonEncode(verdict.toJson()));
      return verdict.passed ? 0 : 1;
    }

    final E2eVerdict verdict = await _service.runSession(
      E2eSessionRequest(
        goal: goal,
        appDir: appDir,
        model: model,
        modelId: modelId,
        device: device,
        extensions: extensions,
        cliPrefix: cliPrefix,
        doneReasonPattern: _optional(arguments.option('done-reason-pattern')),
        doneEvidencePattern: _optional(
          arguments.option('done-evidence-pattern'),
        ),
        expectation: E2eObservationExpectation(
          route: _optional(arguments.option('expect-route')),
          semanticsLabel: label,
          semanticsState: state,
        ),
      ),
    );
    _out.writeln(jsonEncode(verdict.toJson()));
    return verdict.passed ? 0 : 1;
  }

  int _refuse(String message) {
    _err
      ..writeln('e2e: $message')
      ..writeln()
      ..writeln(usage);
    return 64;
  }
}

String? _optional(String? value) {
  final String normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
