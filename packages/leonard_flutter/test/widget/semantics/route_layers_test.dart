import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

void main() {
  // Captures once and returns the route layers, each checked to point at an
  // emitted record.
  Future<List<Map<String, Object?>>> captureLayers() async {
    final SemanticsCapture cap = SemanticsCapture();
    try {
      final SemanticsSnapshot snap = await cap.captureSnapshotAsync();
      final Set<Object> ids = snap.nodes
          .map((Map<String, Object> r) => r['id']!)
          .toSet();
      for (final Map<String, Object?> l in snap.routeLayers) {
        expect(ids, contains(l['node']), reason: 'layer $l names no record');
      }
      return snap.routeLayers;
    } finally {
      cap.dispose();
    }
  }

  List<Object?> names(List<Map<String, Object?>> layers) =>
      layers.map((Map<String, Object?> l) => l['name']).toList();

  Widget home({Key? key, GlobalKey<NavigatorState>? nav}) => MaterialApp(
    key: key,
    navigatorKey: nav,
    home: Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Text('body'),
    ),
  );

  testWidgets('a page alone is one layer, named by its app bar title where '
      'the platform lets the title name the route', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    try {
      await tester.pumpWidget(home());
      expect(names(await captureLayers()), <Object?>['Home']);

      // On iOS the Material app bar title does not name the route.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(home(key: const ValueKey<String>('ios')));
      expect(names(await captureLayers()), <Object?>[null]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      h.dispose();
    }
  });

  testWidgets(
    'a dialog is a named layer on top of the page under it (lenny-kyfdc: '
    'routeStack went empty while a dialog was open)',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      try {
        await tester.pumpWidget(home(nav: nav));
        unawaited(
          showDialog<void>(
            context: nav.currentContext!,
            builder: (_) => const AlertDialog(title: Text('Delete account?')),
          ),
        );
        await tester.pumpAndSettle();
        // The modal barrier hides the page from semantics, so the dialog is
        // the only layer. showDialog scopes its route and AlertDialog scopes
        // itself again; the two fold into one layer, named with AlertDialog's
        // semantic label, the localized "Alert", not its title.
        expect(names(await captureLayers()), <Object?>['Alert']);
      } finally {
        h.dispose();
      }
    },
  );

  testWidgets('a modal bottom sheet is the top layer', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    try {
      await tester.pumpWidget(home(nav: nav));
      unawaited(
        showModalBottomSheet<void>(
          context: nav.currentContext!,
          builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
        ),
      );
      await tester.pumpAndSettle();
      // The sheet's barrier hides the page, so the sheet is the only layer.
      expect(names(await captureLayers()), <Object?>['Dialog']);
    } finally {
      h.dispose();
    }
  });

  testWidgets('a nested navigator in an IndexedStack shows only the selected '
      "tab's route", (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    try {
      Navigator tab(String name) => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => Semantics(
            namesRoute: true,
            label: name,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexedStack(
              index: 1,
              children: <Widget>[tab('tab a'), tab('tab b')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The outer page has no title or content of its own, so it folds with
      // the selected tab's route into one layer; tab a is absent.
      expect(names(await captureLayers()), <Object?>['tab b']);
    } finally {
      h.dispose();
    }
  });

  testWidgets('a titled page around a nested navigator stays its own layer, '
      'under the nested route', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Home')),
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Semantics(
                  namesRoute: true,
                  label: 'inbox',
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(names(await captureLayers()), <Object?>['Home', 'inbox']);
    } finally {
      h.dispose();
    }
  });

  testWidgets('route layers come from the same walk as the nodes and are '
      'empty with them when no semantics tree is found', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final SemanticsCapture cap = SemanticsCapture();
    try {
      await tester.pumpWidget(home());
      expect((await cap.captureSnapshotAsync()).routeLayers, isNotEmpty);
      // No root and no frame coming: the capture times out with nothing,
      // and must not hand back the previous screen's layers.
      // runAsync gives the 250 ms timeout a real clock to fire on.
      cap.debugRaceNextRootLookup = true;
      final SemanticsSnapshot empty = (await tester.runAsync(
        cap.captureSnapshotAsync,
      ))!;
      expect(empty.nodes, isEmpty);
      expect(empty.routeLayers, isEmpty);
    } finally {
      cap.dispose();
      h.dispose();
    }
  });
}
