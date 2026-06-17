/// `leonard_drive` — a thin, stateless VM-service driver so an EXTERNAL
/// agent (e.g. Claude Code) can be the brain: observe the app, decide,
/// invoke a tool, repeat. Unlike `leonard_cli` (which runs lenny's own
/// autonomous LLM loop), this command makes NO model calls — each
/// invocation connects, performs one operation, prints JSON, disconnects.
///
/// Subcommands (all require `--vm-uri ws://…/ws`):
///
///   tools    — handshake; print the available tool manifest
///              { contract_version, namespaces: [ {namespace, tools:[…]} ] }
///   observe  — print the current stable observation as JSON; `--policy`
///              selects the stability policy (default action-relative).
///   invoke   — call one tool: `--tool core.tap --args '{"node_id":5}'`;
///              prints the tool result { ok, value | error }.
///   screenshot — capture a still: decode `core.screenshot` and write the PNG
///              to `--out path.png`; prints { out, width_px, height_px,
///              device_pixel_ratio }. Debug/profile builds only. Just pixels —
///              no settle, no golden compare (the caller owns those).
///
/// Statelessness: every call opens a fresh VM-service session and runs
/// the handshake (which resets the per-session terminal latch), so the
/// external brain owns all turn state. Each `observe` returns the FULL
/// current observation — the brain compares turns itself; there is no
/// server-side diff (that is the autonomous loop's optimization).
///
/// Exit codes: 0 ok · 64 usage error · 1 runtime/connection error. All
/// machine output goes to stdout as a single JSON object; diagnostics go
/// to stderr.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leonard_agent/leonard_agent.dart';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

const String _placeholderGoal = 'external-driver';

StabilityPolicy _policy(String name) => switch (name) {
  'idle' => StabilityPolicy.quietFrame,
  'frame-stable' => StabilityPolicy.boundedStability,
  'action-relative' => StabilityPolicy.actionRelative,
  _ => throw const FormatException('invalid --policy'),
};

ArgParser _parser() => ArgParser()
  ..addOption('vm-uri', help: 'Flutter VM service ws:// URI (required).')
  ..addOption(
    'policy',
    defaultsTo: 'action-relative',
    allowed: <String>['idle', 'frame-stable', 'action-relative'],
    help: 'Stability policy for observe.',
  )
  ..addOption('tool', help: 'Fully-qualified tool name, e.g. core.tap.')
  ..addOption('args', help: 'JSON object of tool arguments (default {}).')
  ..addOption('out', help: 'screenshot: file path to write the PNG to.')
  ..addFlag('help', abbr: 'h', negatable: false);

Future<int> _run(List<String> argv) async {
  if (argv.isEmpty || argv.contains('-h') || argv.contains('--help')) {
    _usage(stdout);
    return argv.isEmpty ? 64 : 0;
  }
  final String command = argv.first;
  if (!const <String>{
    'tools',
    'observe',
    'invoke',
    'screenshot',
  }.contains(command)) {
    stderr.writeln('error: unknown command "$command"');
    _usage(stderr);
    return 64;
  }

  final ArgResults res;
  try {
    res = _parser().parse(argv.sublist(1));
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 64;
  }

  final String? rawUri = res['vm-uri'] as String?;
  final Uri? vmUri = rawUri == null ? null : Uri.tryParse(rawUri);
  if (vmUri == null || (!vmUri.isScheme('ws') && !vmUri.isScheme('wss'))) {
    stderr.writeln('error: --vm-uri must be a ws:// or wss:// URI');
    return 64;
  }

  final String? outPath = res['out'] as String?;
  if (command == 'screenshot' && (outPath == null || outPath.isEmpty)) {
    stderr.writeln('error: screenshot requires --out <path.png>');
    return 64;
  }

  LeonardSession? session;
  try {
    session = await LeonardSession.connect(vmUri);
    // start() runs the handshake (and resets the terminal latch), priming
    // the session for observe/act. The goal is only stamped on an event.
    await session.start(_placeholderGoal, const LeonardConfig());

    switch (command) {
      case 'tools':
        _emit(<String, dynamic>{
          'contract_version': session.handshake.contractVersion,
          'namespaces': <Map<String, dynamic>>[
            for (final ExtensionManifestEntry e in session.handshake.extensions)
              <String, dynamic>{'namespace': e.namespace, 'tools': e.tools},
          ],
        });
        return 0;

      case 'observe':
        final StabilityPolicy policy = _policy(res['policy'] as String);
        final Observation curr = await session.observe(policy: policy);
        _emit(<String, dynamic>{'observation': curr.toJson()});
        return 0;

      case 'invoke':
        final String? tool = res['tool'] as String?;
        if (tool == null || tool.isEmpty) {
          stderr.writeln('error: invoke requires --tool <namespace.tool>');
          return 64;
        }
        final Map<String, dynamic> args;
        try {
          final String raw = (res['args'] as String?) ?? '{}';
          final Object? decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
          if (decoded is! Map) {
            stderr.writeln('error: --args must be a JSON object');
            return 64;
          }
          args = decoded.cast<String, dynamic>();
        } on FormatException catch (e) {
          stderr.writeln('error: --args is not valid JSON: ${e.message}');
          return 64;
        }
        final Map<String, dynamic> result = await session.act(<String, dynamic>{
          'name': tool,
          'args': args,
        });
        _emit(<String, dynamic>{'tool': tool, 'result': result});
        return 0;

      case 'screenshot':
        // core.screenshot is a raw VM extension (not a manifest tool);
        // executeAction routes `core.screenshot` ->
        // ext.exploration.core.screenshot, whose body is
        // { result: { png_base64, width_px, height_px, device_pixel_ratio } }.
        final Map<String, dynamic> shot = await session.act(<String, dynamic>{
          'name': 'core.screenshot',
          'args': <String, dynamic>{},
        });
        final Object? inner = shot['result'];
        if (inner is! Map) {
          stderr.writeln('error: screenshot unavailable (no result payload)');
          return 1;
        }
        final Object? b64 = inner['png_base64'];
        if (b64 is! String || b64.isEmpty) {
          stderr.writeln('error: screenshot unavailable (no png_base64)');
          return 1;
        }
        final File outFile = File(outPath!);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(base64Decode(b64), flush: true);
        _emit(<String, dynamic>{
          'out': outFile.path,
          'width_px': inner['width_px'],
          'height_px': inner['height_px'],
          'device_pixel_ratio': inner['device_pixel_ratio'],
        });
        return 0;
    }
    return 0;
  } on Object catch (e) {
    stderr.writeln('error: $e');
    return 1;
  } finally {
    await session?.end();
  }
}

void _emit(Map<String, dynamic> obj) =>
    stdout.writeln(const JsonEncoder().convert(obj));

void _usage(IOSink out) {
  out.writeln(
    'Usage: leonard_drive <tools|observe|invoke|screenshot> --vm-uri <ws> [...]',
  );
  out.writeln();
  out.writeln('  tools       --vm-uri <ws>');
  out.writeln('  observe     --vm-uri <ws> [--policy P]');
  out.writeln(
    '  invoke      --vm-uri <ws> --tool core.tap --args \'{"node_id":5}\'',
  );
  out.writeln('  screenshot  --vm-uri <ws> --out path.png');
  out.writeln();
  out.writeln(_parser().usage);
}
