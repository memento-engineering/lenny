import 'dart:async';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every `SystemChannels.platform` call so a test can assert the app
/// was never told to exit (`SystemNavigator.pop`). A fake handler, not a
/// mock: it just answers `null` and remembers.
List<MethodCall> _recordPlatformCalls(WidgetTester tester) {
  final List<MethodCall> calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Iterable<MethodCall> _exits(List<MethodCall> calls) =>
    calls.where((MethodCall c) => c.method == 'SystemNavigator.pop');

Future<ToolResult> _systemBack() async {
  final SemanticsCapture cap = SemanticsCapture();
  addTearDown(cap.dispose);
  final CoreExtension plugin = CoreExtension(semantics: cap);
  final LeonardTool sb = plugin.tools.firstWhere(
    (LeonardTool t) => t.name == 'system_back',
  );
  return sb.call(const <String, Object?>{});
}

final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

Widget _app({Widget home = const Text('Home')}) => MaterialApp(
  navigatorKey: _nav,
  home: Scaffold(body: home),
);

void main() {
  testWidgets('pops a pushed route back to the first and reports popped', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = _recordPlatformCalls(tester);
    await tester.pumpWidget(_app());
    unawaited(
      _nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Detail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);

    final ToolResult r = await _systemBack();
    await tester.pumpAndSettle();

    expect(r.ok, isTrue, reason: r.error);
    expect(r.value, <String, Object?>{'handled': true, 'popped': true});
    expect(find.text('Detail'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(_exits(calls), isEmpty);
  });

  testWidgets('at the root reports popped false and never exits the app '
      '(lenny-ssviv)', (WidgetTester tester) async {
    final List<MethodCall> calls = _recordPlatformCalls(tester);
    await tester.pumpWidget(_app());

    final ToolResult r = await _systemBack();
    await tester.pumpAndSettle();

    expect(r.ok, isTrue, reason: r.error);
    expect(r.value, <String, Object?>{'handled': false, 'popped': false});
    expect(find.text('Home'), findsOneWidget);
    expect(_exits(calls), isEmpty);
  });

  testWidgets('a PopScope(canPop: false) route consumes the back without '
      'popping', (WidgetTester tester) async {
    final List<MethodCall> calls = _recordPlatformCalls(tester);
    int blocked = 0;
    await tester.pumpWidget(_app());
    unawaited(
      _nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, void _) {
              if (!didPop) blocked++;
            },
            child: const Scaffold(body: Text('Guarded')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ToolResult r = await _systemBack();
    await tester.pumpAndSettle();

    expect(r.ok, isTrue, reason: r.error);
    expect(r.value, <String, Object?>{'handled': true, 'popped': false});
    expect(blocked, 1);
    expect(find.text('Guarded'), findsOneWidget);
    expect(_exits(calls), isEmpty);
  });

  testWidgets('a Router app pops through its back button dispatcher', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = _recordPlatformCalls(tester);
    final _PagesDelegate delegate = _PagesDelegate();
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: delegate,
        backButtonDispatcher: RootBackButtonDispatcher(),
      ),
    );
    delegate.open('Detail');
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);

    final ToolResult first = await _systemBack();
    await tester.pumpAndSettle();
    expect(first.value, <String, Object?>{'handled': true, 'popped': true});
    expect(find.text('Home'), findsOneWidget);

    final ToolResult atRoot = await _systemBack();
    await tester.pumpAndSettle();
    expect(atRoot.value, <String, Object?>{'handled': false, 'popped': false});
    expect(find.text('Home'), findsOneWidget);
    expect(_exits(calls), isEmpty);
  });
}

/// A minimal pages-based [RouterDelegate]: a stack of named pages whose
/// [popRoute] defers to its navigator's `maybePop`, as go_router's does.
class _PagesDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  final List<String> _stack = <String>['Home'];

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void open(String name) {
    _stack.add(name);
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: <Page<void>>[
      for (final String name in _stack)
        MaterialPage<void>(
          key: ValueKey<String>(name),
          child: Scaffold(body: Text(name)),
        ),
    ],
    onDidRemovePage: (Page<Object?> page) {
      _stack.remove((page.key! as ValueKey<String>).value);
      notifyListeners();
    },
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}
