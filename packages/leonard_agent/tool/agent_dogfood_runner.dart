// Runtime half of the dogfood CLI (bead lenny-cx6.43).
//
// Invoked via `flutter test` because the in-process binding boot
// requires the Flutter SDK; see the rationale comment in
// `tool/agent_dogfood.dart`. Configuration is passed through
// `--dart-define=DOGFOOD_ARGS_JSON=<encoded>` and the resulting exit
// code is written to `--dart-define=DOGFOOD_RESULT_PATH` so the parent
// shim can recover it.
//
// `LeonardBinding.ensureInitialized` is invoked with
// `installCoreExtension: false` (lenny-cx6.45) so the runner can register
// its own `_StandInExtension('core', toolNames)` alongside the non-core
// stand-ins. The dogfood loop exercises model tool selection over the
// full namespace surface — including `core.*` — without booting a
// real widget tree. Without this seam the real CoreExtension's `core.tap`
// dispatches against a missing widget tree and crashes the loop as
// `HarnessError.connectionLost`.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member
//
// `debugSetPolicyLoopSeamsForTesting` is `@visibleForTesting`; the
// runner is test-adjacent and runs under `flutter test`, so the lint
// is suppressed here for the same reason as the e2e test.
library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart' show TrajectorySink;
import 'package:leonard_agent/src/dogfood/agent_dogfood_harness.dart';
import 'package:leonard_agent/src/dogfood/observation_fixture.dart';
import 'package:leonard_agent/src/dogfood/types.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_config.dart';
import 'package:leonard_agent/src/provider/types.dart' show ToolDescriptor;
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leonard_flutter/test_support/binding_vm_service_fake.dart';

/// File-backed [TrajectorySink] used by the CLI shim. Inlined here to
/// avoid `leonard_cli` becoming a runtime dependency.
class _FileSink implements TrajectorySink {
  _FileSink._(this._sink, this.path);
  final IOSink _sink;
  final String path;
  bool _closed = false;

  static Future<_FileSink> open(String path) async {
    final File f = File(path);
    await f.parent.create(recursive: true);
    final IOSink sink = f.openWrite(mode: FileMode.append, encoding: utf8);
    return _FileSink._(sink, path);
  }

  @override
  Future<void> writeLine(String line) async => _sink.writeln(line);

  @override
  Future<void> flush() async {
    if (_closed) return;
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sink.flush();
    await _sink.close();
  }
}

class _StandInExtension extends LeonardExtension {
  _StandInExtension(this._ns, this._all);
  final String _ns;
  final List<String> _all;
  @override
  String get namespace => _ns;
  @override
  List<LeonardTool> get tools => <LeonardTool>[
    for (final String t in _all)
      if (t.startsWith('$_ns.')) _NoopTool(t.substring(_ns.length + 1)),
  ];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _NoopTool extends LeonardTool {
  _NoopTool(this._name);
  final String _name;
  @override
  String get name => _name;
  @override
  String get description => 'dogfood stand-in';
  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args);
}

const String _kArgsJson = String.fromEnvironment(
  'DOGFOOD_ARGS_JSON',
  defaultValue: '',
);
const String _kResultPath = String.fromEnvironment(
  'DOGFOOD_RESULT_PATH',
  defaultValue: '',
);

Future<int> _writeResult(int exitCode) async {
  if (_kResultPath.isNotEmpty) {
    await File(
      _kResultPath,
    ).writeAsString(jsonEncode(<String, Object?>{'exit_code': exitCode}));
  }
  return exitCode;
}

void main() {
  // The runner is shaped as a `flutter test` file (one test()) so the
  // existing test harness's binding bootstrap and reporter machinery
  // can be reused. The actual dogfood loop is wrapped in a single
  // test() body; the test always passes — the dogfood exit code is
  // written to the result file regardless.
  test('agent_dogfood runtime', () async {
    if (_kArgsJson.isEmpty) {
      await _writeResult(3);
      fail('DOGFOOD_ARGS_JSON dart-define is required');
    }
    final Map<String, dynamic> args =
        jsonDecode(_kArgsJson) as Map<String, dynamic>;
    final String goal = args['goal'] as String;
    final List<String> toolNames = (args['tools'] as List<dynamic>)
        .cast<String>();
    final String endpoint = args['endpoint'] as String;
    final String token = args['token'] as String;
    final String model = args['model'] as String;
    final String? fixturePath = args['observation_fixture'] as String?;
    final int maxTurns = (args['max_turns'] as num).toInt();
    final int maxTurnBudgetMs = (args['max_turn_budget_ms'] as num).toInt();
    final bool verbose = args['verbose'] as bool;
    final String tracePath = args['trace_out'] as String;
    // Default captureBodies=true so swift-infer's admin trace retains
    // the request/response bodies for downstream `debug-inference`
    // analysis. Older arg blobs (pre-lenny-cx6.44) lacking the key
    // still get capture on. CLI may opt out via `--no-capture-bodies`.
    final bool captureBodies = (args['capture_bodies'] as bool?) ?? true;

    if (fixturePath != null && !await File(fixturePath).exists()) {
      stderr.writeln('observation fixture not found: $fixturePath');
      await _writeResult(3);
      return;
    }
    final ObservationFixture fixture = fixturePath == null
        ? ObservationFixture.empty()
        : await ObservationFixture.loadFromFile(fixturePath);

    final Set<String> namespaces = toolNames
        .map((String t) => t.split('.').first)
        .toSet();
    final LeonardBinding binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[
        for (final String ns in namespaces) _StandInExtension(ns, toolNames),
      ],
      installCoreExtension: false,
    )!;
    await Future<void>.delayed(Duration.zero);
    int now = 0;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {
        now += 16;
      },
      nowMs: () => now,
    );

    // Wire the loaded fixture into the binding fake so the agent's
    // `core.get_stable_observation` calls return the fixture body
    // instead of the real binding's empty-tree response (lenny-cx6.48).
    final BindingVmServiceFake fake = BindingVmServiceFake(
      binding,
      observationFixture: fixture,
    );
    final _FileSink sink = await _FileSink.open(tracePath);

    final AgentDogfoodHarness harness = AgentDogfoodHarness(
      vm: fake,
      isolateId: 'isolate-0',
      swiftInferConfig: SwiftInferConfig(
        baseUrl: Uri.parse(endpoint),
        model: model,
        bearerToken: token,
        captureBodies: captureBodies,
      ),
      goal: goal,
      tools: <ToolDescriptor>[
        for (final String t in toolNames)
          ToolDescriptor(
            name: t,
            description: 'dogfood-injected $t',
            inputSchema: const <String, dynamic>{'type': 'object'},
          ),
      ],
      fixture: fixture,
      maxTurns: maxTurns,
      maxTurnBudgetMs: maxTurnBudgetMs,
      traceSink: sink,
      tracePath: tracePath,
      verbose: verbose,
      log: (String l) => stdout.writeln(l),
    );

    final DogfoodRunResult result = await harness.run();
    stdout.writeln(
      'dogfood: outcome=${result.outcome.name} '
      'tools=${result.toolCallCount} trace=$tracePath',
    );
    final int exitCode = switch (result.outcome) {
      DogfoodOutcome.completedWithToolCall => 0,
      DogfoodOutcome.completedNoToolCall => 0,
      DogfoodOutcome.typedException => () {
        final Object? exc = result.exception;
        stderr.writeln('${exc.runtimeType}: $exc');
        return 1;
      }(),
      DogfoodOutcome.budgetExceeded => 2,
    };
    await _writeResult(exitCode);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
