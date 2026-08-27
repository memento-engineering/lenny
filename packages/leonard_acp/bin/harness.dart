/// Phase-1 measurement harness: run a REAL LoopDriver session with an ACP
/// agent as the provider and report the SchemaRejection rate.
///
/// One clean turn in `bin/probe.dart` is not evidence. This runs the full
/// 10-step loop against [ScriptedCounterHost] — real observation payloads, a
/// `oneOf` schema over the merged tool list, and the three-pass
/// [ActionValidator] — and produces the number that decides whether phase 2's
/// MCP tool-calling is warranted.
///
/// Usage:
///   dart run leonard_acp:harness
///   dart run leonard_acp:harness --agent copilot --turns 20 --target 3
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:leonard_acp/leonard_acp.dart';
import 'package:leonard_agent/leonard_agent.dart';

/// Discards trajectory lines — this harness reports from the counting
/// provider, not from the trace.
class _DiscardSink implements TrajectorySink {
  @override
  Future<void> writeLine(String line) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'agent',
      allowed: <String>['codex', 'copilot'],
      defaultsTo: 'codex',
    )
    ..addOption('turns', defaultsTo: '20', help: 'Max turns for the session.')
    ..addOption('target', defaultsTo: '3', help: 'Counter value to reach.')
    ..addFlag('verbose', abbr: 'v', help: 'Echo agent stderr and each turn.');
  final ArgResults args = parser.parse(argv);

  final int maxTurns = int.parse(args['turns'] as String);
  final int target = int.parse(args['target'] as String);
  final bool verbose = args['verbose'] == true;

  final AcpAgentSpec spec = args['agent'] == 'copilot'
      ? AcpAgentSpec.copilot()
      : AcpAgentSpec.codex();

  stdout
    ..writeln('harness: $spec')
    ..writeln('  maxTurns=$maxTurns target=$target')
    ..writeln('');

  final AcpSession session = await AcpSession.start(
    spec,
    onStderr: (String line) {
      if (verbose) stderr.writeln('  [agent] $line');
    },
  );
  final Directory cwd = await Directory.systemTemp.createTemp('leonard_acp_h');

  final ScriptedCounterHost host = ScriptedCounterHost(target: target);
  final CountingModelProvider provider = CountingModelProvider(
    AcpModelProvider(session: session),
  );

  final TrajectoryWriter writer = TrajectoryWriter(_DiscardSink());
  final Stopwatch wall = Stopwatch()..start();
  SessionTermination? termination;
  Object? failure;
  String? sessionModel;

  try {
    await session.newSession(cwd: cwd.path);
    sessionModel = session.modelId;

    await writer.writeHeader(
      SessionHeader(
        goal: host.goal,
        agentsMdHash: kDefaultAgentsMdHash,
        buildIdentifier: 'scripted-counter',
        modelIdentifier: 'acp:${spec.label}',
        harnessVersion: 'leonard_acp-phase1',
        extensions: const <ExtensionManifestRecord>[],
        config: <String, dynamic>{'max_turns': maxTurns, 'target': target},
      ),
    );

    final LoopDriver driver = LoopDriver(
      host: host,
      provider: provider,
      conversation: ConversationBuilder(
        systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
        tools: host.mergedTools(),
      ),
      validator: const ActionValidator(),
      writer: writer,
      maxTurns: maxTurns,
      onTurnEvent: !verbose
          ? null
          : (TurnEvent e) {
              if (e is TurnActionDecided) {
                stdout.writeln('  turn ${e.turn}: ${e.toolName} ${e.args}');
              } else if (e is TurnValidation && !e.ok) {
                stdout.writeln('  turn ${e.turn}: REJECT ${e.rejectReason}');
              }
            },
    );

    termination = await driver.runSession();
  } on Object catch (e) {
    failure = e;
  } finally {
    wall.stop();
    await session.dispose();
    await cwd.delete(recursive: true);
  }

  // ---- report ----------------------------------------------------------
  final int attempts = provider.attempts;
  final String avgMs = attempts == 0
      ? 'n/a'
      : (provider.elapsed.inMilliseconds / attempts).toStringAsFixed(0);

  stdout
    ..writeln('')
    ..writeln('== result ==')
    ..writeln('  model:          ${sessionModel ?? '(agent default)'}')
    ..writeln('  outcome:        ${termination?.outcome.name ?? 'THREW'}')
    ..writeln('  harnessError:   ${termination?.harnessError?.wireName ?? '-'}')
    ..writeln('  counter:        ${host.counter} / $target')
    ..writeln('  goalReached:    ${host.counter >= target}')
    ..writeln('  wallClock:      ${wall.elapsed.inSeconds}s')
    ..writeln('')
    ..writeln('== the number ==')
    ..writeln('  decide() calls: $attempts')
    ..writeln('  rejections:     ${provider.rejections}')
    ..writeln(
      '  rejection rate: ${(provider.rejectionRate * 100).toStringAsFixed(1)}%',
    )
    ..writeln('  avg latency:    ${avgMs}ms/call');

  if (provider.rejectionReasons.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('== rejection reasons ==');
    for (final String r in provider.rejectionReasons) {
      stdout.writeln('  - $r');
    }
  }
  if (failure != null) {
    stdout
      ..writeln('')
      ..writeln('== threw ==')
      ..writeln('  $failure');
    exit(1);
  }
}
