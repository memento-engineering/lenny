/// Day-one ACP handshake probe.
///
/// Answers the two questions that decide whether the phase-1 design holds,
/// against a real agent rather than a doc page:
///
///   1. What protocol version and capabilities does the agent negotiate?
///      (`acp_dart` 0.4.0 speaks ACP v1; the Claude adapter is at 0.70.0.)
///   2. Does a deny-all permission handler yield a clean text-only answer,
///      or does the agent hard-fail / retry-loop when every tool is refused?
///
/// Usage:
///   dart run leonard_acp:probe                 # claude via the ACP adapter
///   dart run leonard_acp:probe --agent copilot
library;

import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:args/args.dart';
import 'package:leonard_acp/leonard_acp.dart';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'agent',
      allowed: <String>['claude', 'copilot'],
      defaultsTo: 'claude',
      help: 'Which ACP agent to probe.',
    )
    ..addFlag('verbose', abbr: 'v', help: 'Echo the agent stderr.');
  final ArgResults args = parser.parse(argv);

  final AcpAgentSpec spec = args['agent'] == 'copilot'
      ? AcpAgentSpec.copilot()
      : AcpAgentSpec.claudeAgent();

  stdout.writeln('probing: $spec');
  final Stopwatch sw = Stopwatch()..start();

  AcpSession? session;
  try {
    session = await AcpSession.start(
      spec,
      onStderr: (String line) {
        if (args['verbose'] == true) stderr.writeln('  [agent] $line');
      },
    );
  } on ProcessException catch (e) {
    stdout.writeln('FAIL spawn: ${e.message}');
    exit(1);
  }

  // ---- Q1: handshake ---------------------------------------------------
  final InitializeResponse? init = session.initializeResponse;
  stdout
    ..writeln('')
    ..writeln('== Q1 handshake (${sw.elapsedMilliseconds}ms) ==')
    ..writeln('  we sent protocolVersion: $kAcpProtocolVersion')
    ..writeln('  agent negotiated:        ${init?.protocolVersion}')
    ..writeln(
      '  agentCapabilities:       ${jsonEncode(init?.agentCapabilities)}',
    );

  if (init != null && init.protocolVersion != kAcpProtocolVersion) {
    stdout.writeln(
      '  !! VERSION SKEW — acp_dart 0.4.0 speaks v$kAcpProtocolVersion',
    );
  }

  // ---- Q2: deny-all permission handling --------------------------------
  final Directory cwd = await Directory.systemTemp.createTemp('leonard_acp_');
  try {
    await session.newSession(cwd: cwd.path);
    stdout
      ..writeln('')
      ..writeln('== Q2 deny-all text-only turn ==')
      ..writeln('  sessionId: ${session.sessionId}');

    sw.reset();
    final AcpTurn turn = await session.prompt(
      'Reply with ONE JSON object and nothing else — no prose, no code '
      'fence: {"action":{"tool":"core.done","args":{"reason":"probe"}}}\n'
      'You have no tools and no file access. Do not read, write, or run '
      'anything.',
    );

    stdout
      ..writeln('  latency:     ${sw.elapsedMilliseconds}ms')
      ..writeln('  stopReason:  ${turn.stopReason.name}')
      ..writeln('  deniedTools: ${turn.deniedTools}')
      ..writeln('  thinking:    ${turn.thinking.length} chars')
      ..writeln('  text:        ${_truncate(turn.text)}');

    final bool cleanJson = _looksLikeBareJson(turn.text);
    stdout
      ..writeln('')
      ..writeln(
        '  VERDICT: '
        '${cleanJson ? "bare JSON returned" : "NOT bare JSON"}'
        '${turn.deniedTools.isEmpty ? "" : " / agent attempted tool use"}',
      );
  } finally {
    await session.dispose();
    await cwd.delete(recursive: true);
  }
}

String _truncate(String s) {
  final String one = s.trim().replaceAll('\n', '\\n');
  return one.length <= 300 ? one : '${one.substring(0, 300)}…';
}

bool _looksLikeBareJson(String s) {
  final String t = s.trim();
  if (!t.startsWith('{') || !t.endsWith('}')) return false;
  try {
    return jsonDecode(t) is Map;
  } on FormatException {
    return false;
  }
}
