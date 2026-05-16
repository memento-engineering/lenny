// CI guard: forbid direct `dart:io` imports inside `exploration_agent/lib`.
// Story .21 will swap the websocket entrypoint for a conditional import,
// after which this guard ensures the harness library stays
// web-compatible per PRD §22.
//
// Allowed: this script lives in `tool/` and may use `dart:io` itself.
// Forbidden: any `.dart` file under `lib/` importing `dart:io` directly,
// EXCEPT files under `lib/src/dogfood/` — that subtree is the dogfood
// harness (bead lenny-cx6.43) and is NOT re-exported from
// `lib/exploration_agent.dart`, so its `dart:io` use cannot leak into
// the web-exported surface.

import 'dart:io';

void main() {
  final hits = <String>[];
  final re = RegExp(r"""import\s+['"]dart:io['"]""");
  final dir = Directory('packages/exploration_agent/lib');
  if (!dir.existsSync()) {
    stderr.writeln('check_no_dart_io: ${dir.path} does not exist '
        '(run from repo root)');
    exit(2);
  }
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    // Whitelist the dogfood subtree — see bead lenny-cx6.43.
    if (f.path.contains('/lib/src/dogfood/')) continue;
    if (re.hasMatch(f.readAsStringSync())) {
      hits.add(f.path);
    }
  }
  if (hits.isNotEmpty) {
    stderr.writeln('dart:io imports forbidden in exploration_agent: $hits');
    exit(1);
  }
  stdout.writeln('OK: no dart:io in exploration_agent/lib '
      '(dogfood subtree whitelisted)');
}
