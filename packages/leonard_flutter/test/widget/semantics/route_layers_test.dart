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
      final List<Map<String, Object>> recs = await cap.captureAsync();
      final Set<Object> ids = recs
          .map((Map<String, Object> r) => r['id']!)
          .toSet();
      for (final Map<String, Object?> l in cap.lastRouteLayers) {
        expect(ids, contains(l['node']), reason: 'layer $l names no record');
      }
      return cap.lastRouteLayers;
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
        // The page stays a layer, but the modal barrier blocks its contents
        // from semantics, app bar title included, so it is unnamed. AlertDialog
        // names its route with its semantic label, which defaults to the
        // localized "Alert", not the title.
        expect(names(await captureLayers()), <Object?>[null, 'Alert']);
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
      expect(names(await captureLayers()).last, 'Dialog');
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
      expect(names(await captureLayers()), <Object?>[null, 'tab b']);
    } finally {
      h.dispose();
    }
  });
}
