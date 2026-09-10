/// Serves an ACP-backed Leonard model provider over a Dart Tooling Daemon.
///
/// Usage:
///   dart run leonard_acp:dtd_host \
///     --dtd-uri ws://127.0.0.1:12345/abc=/ \
///     --dtd-secret trustedJennieHex \
///     --agent codex
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:dtd/dtd.dart';
import 'package:leonard_acp/leonard_acp.dart';

/// Builds the command-line contract for the DTD ACP host.
ArgParser buildDtdHostArgParser() => ArgParser()
  ..addOption('dtd-uri', mandatory: true, help: 'DTD WebSocket URI.')
  ..addOption(
    'dtd-secret',
    mandatory: true,
    help: 'DTD trusted-client secret (never logged).',
  )
  ..addOption(
    'agent',
    allowed: <String>['codex', 'copilot'],
    defaultsTo: 'codex',
    help: 'ACP agent to host.',
  )
  ..addOption(
    'cwd',
    defaultsTo: Directory.current.path,
    help: 'Working directory for the ACP session.',
  )
  ..addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    help: 'Echo the ACP agent stderr.',
  );

/// Connects to DTD and serves a real [AcpModelProvider] until DTD closes.
Future<void> main(List<String> argv) async {
  final ArgParser parser = buildDtdHostArgParser();
  late final ArgResults args;
  try {
    args = parser.parse(argv);
  } on ArgParserException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final String dtdUriArgument = args['dtd-uri'] as String;
  final String dtdSecret = args['dtd-secret'] as String;
  if (dtdUriArgument.trim().isEmpty) {
    stderr.writeln('--dtd-uri must not be empty.');
    exitCode = 64;
    return;
  }
  if (dtdSecret.trim().isEmpty) {
    stderr.writeln('--dtd-secret must not be empty.');
    exitCode = 64;
    return;
  }

  // DTD 4.0 service registration is intentionally unprivileged. The secret
  // is accepted as launch context, but is neither sent nor logged because this
  // executable does not invoke privileged filesystem or VM-service methods.
  final Uri dtdUri = Uri.parse(dtdUriArgument);
  final bool verbose = args['verbose'] == true;
  final AcpAgentSpec spec = args['agent'] == 'copilot'
      ? AcpAgentSpec.copilot()
      : AcpAgentSpec.codex();

  DartToolingDaemon? dtd;
  AcpSession? session;
  DtdAcpHost? host;
  try {
    dtd = await DartToolingDaemon.connect(dtdUri);
    session = await AcpSession.start(
      spec,
      onStderr: verbose
          ? (String line) => stderr.writeln('[agent] $line')
          : null,
    );
    await session.newSession(cwd: args['cwd'] as String);

    final AcpModelProvider provider = AcpModelProvider(session: session);
    host = DtdAcpHost.fromDaemon(dtd, provider);
    final bool started = await host.start(reportError: stderr.writeln);
    if (!started) {
      exitCode = 1;
      return;
    }

    await dtd.done;
  } finally {
    try {
      await host?.dispose();
    } finally {
      try {
        await session?.dispose();
      } finally {
        if (dtd != null && !dtd.isClosed) await dtd.close();
      }
    }
  }
}
