/// `dart run leonard_cli:install` — install Leonard's consumer-facing
/// coding-agent assets (the `drive-with-leonard` skill + `leonard-driver`/
/// `leonard-pilot` agents) into the current repo.
///
/// The canonical copy always lands in `.agents/` (the cross-client agentskills
/// convention). Harness flags then overlay that single source into each
/// harness's native location as **symlinks** (falling back to copies where the
/// platform doesn't support symlinks), so there's one source of truth to edit:
///
///   dart run leonard_cli:install                 # .agents/ only (cross-client)
///   dart run leonard_cli:install --claude        # + .claude/{agents,skills} symlinks
///   dart run leonard_cli:install --copilot       # + root agents/ skills/ (Copilot CLI plugin)
///   dart run leonard_cli:install --all           # every harness
///   dart run leonard_cli:install --dir DIR       # target DIR instead of cwd
///   dart run leonard_cli:install --force         # overwrite existing entries
///
/// Idempotent: existing `.agents/` entries are skipped unless `--force`;
/// existing leonard-managed symlinks are refreshed. Assets are bundled in the
/// package (`lib/assets/`) and resolved from the pub cache — no network.
library;

import 'dart:io';
import 'dart:isolate';

void _log(String m) => stdout.writeln(m);

Future<void> main(List<String> argv) async {
  bool force = false, claude = false, copilot = false;
  String targetRoot = Directory.current.path;
  for (int i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--force':
        force = true;
      case '--claude':
        claude = true;
      case '--copilot':
        copilot = true;
      case '--all':
        claude = true;
        copilot = true;
      case '--dir':
        if (i + 1 >= argv.length) {
          stderr.writeln('error: --dir requires a path');
          exitCode = 64;
          return;
        }
        targetRoot = argv[++i];
      case '-h':
      case '--help':
        stdout.writeln(
          'Usage: dart run leonard_cli:install '
          '[--dir DIR] [--claude] [--copilot] [--all] [--force]\n'
          'Installs the drive-with-leonard skill + leonard-driver/leonard-pilot '
          'agents into DIR/.agents/ (default cwd), with optional harness '
          'overlays (--claude, --copilot).',
        );
        return;
      default:
        stderr.writeln('error: unknown argument "${argv[i]}"');
        exitCode = 64;
        return;
    }
  }

  final Directory? assets = await _resolveAssets();
  if (assets == null) {
    exitCode = 1;
    return;
  }

  // 1. Canonical cross-client copy into .agents/{skills,agents}.
  final String dotAgents = '$targetRoot/.agents';
  int added = 0, skipped = 0;
  final List<String> agentBaseNames = <String>[]; // e.g. leonard-pilot
  final List<String> skillNames = <String>[]; // e.g. drive-with-leonard
  for (final String kind in const <String>['skills', 'agents']) {
    final Directory src = Directory('${assets.path}$kind');
    if (!src.existsSync()) continue;
    for (final FileSystemEntity entity in src.listSync()) {
      final String name = _basename(entity.path);
      if (kind == 'skills') skillNames.add(name);
      if (kind == 'agents') {
        agentBaseNames.add(name.replaceFirst('.agent.md', ''));
      }
      final String dest = '$dotAgents/$kind/$name';
      if (_exists(dest) && !force) {
        _log('  skip   .agents/$kind/$name (exists; --force to overwrite)');
        skipped++;
        continue;
      }
      if (entity is Directory) {
        _copyDir(entity, Directory(dest));
      } else if (entity is File) {
        Directory('$dotAgents/$kind').createSync(recursive: true);
        entity.copySync(dest);
      }
      _log('  add    .agents/$kind/$name');
      added++;
    }
  }

  // 2. Harness overlays — symlink the canonical .agents/ entries into each
  // harness's native location (single source of truth).
  if (claude) {
    _log('\nClaude Code overlay (.claude/):');
    for (final String base in agentBaseNames) {
      // Claude reads .claude/agents/<name>.md
      _overlay(
        '$targetRoot/.claude/agents/$base.md',
        '../../.agents/agents/$base.agent.md',
        force: force,
      );
    }
    for (final String name in skillNames) {
      _overlay(
        '$targetRoot/.claude/skills/$name',
        '../../.agents/skills/$name',
        force: force,
      );
    }
  }
  if (copilot) {
    // GitHub Copilot CLI plugin layout: agents/*.agent.md + skills/<name>/ at
    // the plugin (repo) root. Point them at the canonical .agents/.
    _log('\nGitHub Copilot CLI overlay (repo-root plugin layout):');
    _overlay('$targetRoot/agents', '.agents/agents', force: force);
    _overlay('$targetRoot/skills', '.agents/skills', force: force);
  }

  _log(
    '\nInstalled $added item(s) into $dotAgents'
    '${skipped > 0 ? ' ($skipped skipped)' : ''}'
    '${claude || copilot ? ' + harness overlays' : ''}.\n'
    'Your coding agent can now use the "drive-with-leonard" skill and the\n'
    'leonard-driver / leonard-pilot agents. See the skill for setup.',
  );
}

/// Resolve the bundled `lib/assets/` dir from the pub cache.
Future<Directory?> _resolveAssets() async {
  final Uri? libEntry = await Isolate.resolvePackageUri(
    Uri.parse('package:leonard_cli/leonard_cli.dart'),
  );
  if (libEntry == null) {
    stderr.writeln('error: could not resolve the leonard_cli package location');
    return null;
  }
  final Directory assets = Directory.fromUri(libEntry.resolve('assets/'));
  if (!assets.existsSync()) {
    stderr.writeln('error: bundled assets not found at ${assets.path}');
    return null;
  }
  return assets;
}

/// Create [linkPath] as a symlink to [relTarget] (relative to the link's own
/// directory). Idempotent: refreshes a stale leonard symlink; skips a real
/// (non-symlink) file/dir unless [force]; falls back to a copy when the
/// platform rejects symlinks.
void _overlay(String linkPath, String relTarget, {required bool force}) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    linkPath,
    followLinks: false,
  );
  if (type == FileSystemEntityType.link) {
    Link(linkPath).deleteSync(); // refresh
  } else if (type != FileSystemEntityType.notFound) {
    if (!force) {
      _log(
        '  skip   $linkPath (exists, not a leonard link; --force to replace)',
      );
      return;
    }
    if (FileSystemEntity.isDirectorySync(linkPath)) {
      Directory(linkPath).deleteSync(recursive: true);
    } else {
      File(linkPath).deleteSync();
    }
  }
  Directory(File(linkPath).parent.path).createSync(recursive: true);
  try {
    Link(linkPath).createSync(relTarget);
    _log('  link   ${_rel(linkPath)} -> $relTarget');
  } on FileSystemException {
    // Symlinks unsupported (e.g. Windows without dev mode): copy instead.
    final String resolved = File(
      '${File(linkPath).parent.path}/$relTarget',
    ).absolute.path;
    final FileSystemEntityType rt = FileSystemEntity.typeSync(resolved);
    if (rt == FileSystemEntityType.directory) {
      _copyDir(Directory(resolved), Directory(linkPath));
    } else if (rt == FileSystemEntityType.file) {
      File(resolved).copySync(linkPath);
    }
    _log('  copy   ${_rel(linkPath)} (symlink unsupported)');
  }
}

bool _exists(String p) =>
    FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound;

String _basename(String p) =>
    Uri.file(p).pathSegments.where((String s) => s.isNotEmpty).last;

String _rel(String p) {
  final String cwd = Directory.current.path;
  return p.startsWith('$cwd/') ? p.substring(cwd.length + 1) : p;
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
