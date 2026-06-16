/// `dart run leonard_cli:install` — copy Leonard's consumer-facing coding-agent
/// assets (the `drive-flutter-app` skill + `leonard-driver`/`leonard-pilot`
/// agents) into the current repo's `.agents/` directory, the cross-client
/// convention scanned by agentskills-compatible coding agents (Claude Code,
/// GitHub Copilot CLI, …). Run it once from your app's repo root:
///
///   dart run leonard_cli:install            # into ./.agents/
///   dart run leonard_cli:install --dir DIR  # into DIR/.agents/
///   dart run leonard_cli:install --force    # overwrite existing copies
///
/// Idempotent: existing entries are skipped unless `--force`, so your local
/// edits are never clobbered. Assets are bundled in the package
/// (`lib/assets/`) and resolved from the pub cache at runtime — no network.
library;

import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> argv) async {
  bool force = false;
  String targetRoot = Directory.current.path;
  for (int i = 0; i < argv.length; i++) {
    final String a = argv[i];
    if (a == '--force') {
      force = true;
    } else if (a == '--dir') {
      if (i + 1 >= argv.length) {
        stderr.writeln('error: --dir requires a path');
        exitCode = 64;
        return;
      }
      targetRoot = argv[++i];
    } else if (a == '-h' || a == '--help') {
      stdout.writeln(
        'Usage: dart run leonard_cli:install [--dir <repo-root>] [--force]\n'
        'Copies the drive-flutter-app skill + leonard-driver/leonard-pilot '
        'agents into <repo-root>/.agents/ for your coding agent.',
      );
      return;
    } else {
      stderr.writeln('error: unknown argument "$a"');
      exitCode = 64;
      return;
    }
  }

  // Resolve the bundled assets dir from this package (works from the pub
  // cache): package:leonard_cli/leonard_cli.dart -> lib/ -> lib/assets/.
  final Uri? libEntry = await Isolate.resolvePackageUri(
    Uri.parse('package:leonard_cli/leonard_cli.dart'),
  );
  if (libEntry == null) {
    stderr.writeln('error: could not resolve the leonard_cli package location');
    exitCode = 1;
    return;
  }
  final Directory assets = Directory.fromUri(libEntry.resolve('assets/'));
  if (!assets.existsSync()) {
    stderr.writeln('error: bundled assets not found at ${assets.path}');
    exitCode = 1;
    return;
  }

  final Directory dotAgents = Directory('$targetRoot/.agents');
  int copied = 0;
  int skipped = 0;

  // skills/<name>/  and  agents/<name>.agent.md  mirror straight across.
  for (final String kind in const <String>['skills', 'agents']) {
    final Directory src = Directory('${assets.path}$kind');
    if (!src.existsSync()) continue;
    for (final FileSystemEntity entity in src.listSync()) {
      final String name = entity.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      final String destPath = '${dotAgents.path}/$kind/$name';
      final bool exists =
          FileSystemEntity.typeSync(destPath) != FileSystemEntityType.notFound;
      if (exists && !force) {
        stdout.writeln(
          '  skip   .agents/$kind/$name (exists; --force to overwrite)',
        );
        skipped++;
        continue;
      }
      if (entity is Directory) {
        _copyDir(entity, Directory(destPath));
      } else if (entity is File) {
        Directory('${dotAgents.path}/$kind').createSync(recursive: true);
        entity.copySync(destPath);
      }
      stdout.writeln('  ${exists ? 'update' : 'add   '} .agents/$kind/$name');
      copied++;
    }
  }

  stdout.writeln(
    '\nInstalled $copied item(s) into ${dotAgents.path}'
    '${skipped > 0 ? ' ($skipped skipped)' : ''}.\n'
    'Your coding agent can now use the "drive-flutter-app" skill and the\n'
    'leonard-driver / leonard-pilot agents. See the skill for setup.',
  );
}

void _copyDir(Directory src, Directory dest) {
  dest.createSync(recursive: true);
  for (final FileSystemEntity e in src.listSync(recursive: true)) {
    final String rel = e.path.substring(src.path.length);
    final String target = '${dest.path}$rel';
    if (e is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (e is File) {
      Directory(File(target).parent.path).createSync(recursive: true);
      e.copySync(target);
    }
  }
}
