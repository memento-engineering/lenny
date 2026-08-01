/// `lib/main.dart` cannot be imported from a VM `flutter test`: it
/// imports `dart:html`, and `DevToolsExtension` transitively imports
/// `dart:js_interop` / `package:web`. This test therefore gates the
/// production wiring at the SOURCE level — `LeonardDevToolsExtension`
/// must delegate to `LeonardExtensionRoot` and must read no DevTools
/// global in its own build (the ordering regression). The behavioural
/// half lives in `test/extension_root_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locates `leonard_devtools/lib/main.dart` whether the test runner's
/// CWD is the package directory or the repo root.
File _mainDart() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final local = File('${dir.path}/lib/main.dart');
    if (dir.path.endsWith('leonard_devtools') && local.existsSync()) {
      return local;
    }
    final nested = File('${dir.path}/packages/leonard_devtools/lib/main.dart');
    if (nested.existsSync()) return nested;
    dir = dir.parent;
  }
  throw StateError('could not locate leonard_devtools/lib/main.dart');
}

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
