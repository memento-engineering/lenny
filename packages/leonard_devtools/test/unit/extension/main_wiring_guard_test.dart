/// `lib/main.dart` cannot be imported from a VM `flutter test`: it
/// imports `dart:html`, and `DevToolsExtension` transitively imports
/// `dart:js_interop` / `package:web`. This test therefore gates the
/// production wiring at the SOURCE level. It also pins the self-drive
/// entrypoint outside `lib/`, the dev-only Leonard dependency, and the
/// production extension build target.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locates the leonard_devtools package whether the test runner's CWD is
/// the package directory or the repository root.
Directory _packageRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final localPubspec = File('${dir.path}/pubspec.yaml');
    if (dir.path.endsWith('leonard_devtools') &&
        localPubspec.existsSync()) {
      return dir;
    }

    final nested = Directory('${dir.path}/packages/leonard_devtools');
    if (File('${nested.path}/pubspec.yaml').existsSync()) {
      return nested;
    }
    dir = dir.parent;
  }
  throw StateError('could not locate the leonard_devtools package');
}

Directory _repoRoot() => _packageRoot().parent.parent;

Directory _libDirectory() => Directory('${_packageRoot().path}/lib');

File _mainDart() => File('${_packageRoot().path}/lib/main.dart');

File _selfDriveMain() =>
    File('${_packageRoot().path}/dev/selfdrive_main.dart');

File _pubspec() => File('${_packageRoot().path}/pubspec.yaml');

File _readme() => File('${_packageRoot().path}/README.md');

File _buildScript() =>
    File('${_repoRoot().path}/tool/build_devtools_extension.sh');

/// Returns the source of the `LeonardDevToolsExtension` declaration:
/// from its `class` keyword to the start of the next top-level
/// declaration — its doc comment included, so a later comment that
/// merely *names* a global cannot fail the guard.
String _extensionClassBody(String source) {
  const marker = 'class LeonardDevToolsExtension';
  final start = source.indexOf(marker);
  expect(start, isNonNegative, reason: 'LeonardDevToolsExtension not found');
  final next = source.indexOf(
    RegExp(r'\n(///|class |abstract |typedef |void |final |const )'),
    start + marker.length,
  );
  return next == -1 ? source.substring(start) : source.substring(start, next);
}

void main() {
  final String source = _mainDart().readAsStringSync();

  test('LeonardDevToolsExtension delegates to LeonardExtensionRoot', () {
    final body = _extensionClassBody(source);
    expect(body, contains('LeonardExtensionRoot('));
    expect(body, contains('DevToolsExtension(child: child)'));
    expect(body, contains('scopeFactory: _LiveDevToolsScope.new'));
  });

  test('LeonardDevToolsExtension reads no DevTools global', () {
    final body = _extensionClassBody(source);
    expect(body, isNot(contains('serviceManager')));
    expect(body, isNot(contains('dtdManager')));
  });

  test('the globals reads live in _LiveDevToolsScope', () {
    expect(
      source,
      contains('class _LiveDevToolsScope implements LeonardDevToolsScope'),
    );
    expect(source, contains('serviceManager.connectedState'));
    expect(source, contains('serviceManager.isolateManager.mainIsolate'));
  });

  test(
    '_loadDiagnosticsSnapshot borrows the DevTools VM connection and '
    'calls the on-demand sibling only',
    () {
      final String body = _loadDiagnosticsSnapshotBody(source);
      expect(body, contains('serviceManager.service'));
      expect(body, contains('mainIsolate'));
      expect(body, contains('kLeonardExtensionPrefix'));
      expect(body, contains('core.get_diagnostics_tree'));
      // The diagnostics loader must NOT ride the observation hot path,
      // pass stability-policy arguments, or open its own socket.
      expect(body, isNot(contains('core.get_stable_observation')));
      expect(body, isNot(contains('action-relative')));
      expect(body, isNot(contains('vm_service_io.dart')));
    },
  );

  test(
    'self-drive entrypoint installs LeonardBinding before shared shell',
    () {
      final source = _selfDriveMain().readAsStringSync();
      expect(
        source,
        contains(
          "import 'package:leonard_devtools/main.dart' "
          'show LeonardDevToolsExtension;',
        ),
      );
      expect(
        source,
        contains('extensions: const <LeonardExtension>[]'),
      );

      final bindingCall = source.indexOf(
        'LeonardBinding.ensureInitialized(',
      );
      final runAppCall = source.indexOf(
        'runApp(const LeonardDevToolsExtension())',
      );
      expect(bindingCall, isNonNegative);
      expect(runAppCall, greaterThan(bindingCall));
    },
  );

  test('leonard_flutter remains a dev dependency', () {
    final source = _pubspec().readAsStringSync();
    final dependenciesStart = source.indexOf('\ndependencies:\n');
    final devDependenciesStart = source.indexOf(
      '\ndev_dependencies:\n',
    );
    final flutterStart = source.indexOf(
      '\nflutter:\n',
      devDependenciesStart,
    );
    expect(dependenciesStart, isNonNegative);
    expect(devDependenciesStart, greaterThan(dependenciesStart));
    expect(flutterStart, greaterThan(devDependenciesStart));

    final dependencies = source.substring(
      dependenciesStart,
      devDependenciesStart,
    );
    final devDependencies = source.substring(
      devDependenciesStart,
      flutterStart,
    );
    final leonardFlutter = RegExp(
      r'^  leonard_flutter: \^0\.3\.0$',
      multiLine: true,
    );
    expect(dependencies, isNot(matches(leonardFlutter)));
    expect(devDependencies, matches(leonardFlutter));
  });

  test('production lib imports no leonard_flutter', () {
    final packageRootPath = _packageRoot().path;
    final leonardFlutterImport = RegExp(
      r'''^\s*import\s+['"]package:leonard_flutter/''',
      multiLine: true,
    );
    final offenders = _libDirectory()
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => leonardFlutterImport.hasMatch(
            file.readAsStringSync(),
          ),
        )
        .map(
          (file) => file.path.substring(packageRootPath.length + 1),
        )
        .toList()
      ..sort();
    expect(
      offenders,
      isEmpty,
      reason: 'lib/ must not import dev-only leonard_flutter: '
          '$offenders',
    );
  });

  test('extension build keeps lib/main.dart entrypoint', () {
    final source = _buildScript().readAsStringSync();
    final buildCommands = RegExp(
      r'^flutter pub run devtools_extensions build_and_copy \\$',
      multiLine: true,
    ).allMatches(source);
    final defaultSources = RegExp(
      r'^  --source=\. \\$',
      multiLine: true,
    ).allMatches(source);

    expect(buildCommands, hasLength(2));
    expect(defaultSources, hasLength(2));
    expect(source, isNot(contains('dev/selfdrive_main.dart')));
  });

  test('standalone README documents self-drive invocation', () {
    final source = _readme().readAsStringSync();
    final standaloneStart = source.indexOf(
      '### Standalone web (fast iteration)',
    );
    final inDevToolsStart = source.indexOf(
      '### In-DevTools (real handshake)',
    );
    expect(standaloneStart, isNonNegative);
    expect(inDevToolsStart, greaterThan(standaloneStart));

    final standalone = source.substring(
      standaloneStart,
      inDevToolsStart,
    );
    expect(
      standalone,
      contains(
        'flutter run -t dev/selfdrive_main.dart -d chrome '
        '--dart-define=use_simulated_environment=true',
      ),
    );
  });
}

/// Returns the source of `_loadDiagnosticsSnapshot`: from its declaration
/// to the start of the next static member, so surrounding methods (the
/// probe, the session factory) cannot mask a violation.
String _loadDiagnosticsSnapshotBody(String source) {
  const marker = '_loadDiagnosticsSnapshot() async {';
  final start = source.indexOf(marker);
  expect(start, isNonNegative, reason: '_loadDiagnosticsSnapshot not found');
  final next = source.indexOf('static ', start + marker.length);
  return next == -1 ? source.substring(start) : source.substring(start, next);
}
