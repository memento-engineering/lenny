import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/router.dart';
import 'package:sample_app/services/api.dart';
import 'package:sample_app/services/fake_api_adapter.dart';

import 'package:dio/dio.dart';

Dio _instantDio() {
  final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
  dio.httpClientAdapter = FakeApiAdapter(latency: Duration.zero);
  return dio;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  final router = buildRouter(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Login → Home with valid demo credentials', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: <Override>[dioProvider.overrideWithValue(_instantDio())],
    );
    addTearDown(container.dispose);
    await _pumpApp(tester, container);

    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);

    // Fields start EMPTY — type the valid demo credentials,
    // then tap Sign In.
    await tester.enterText(find.byType(TextField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Change Profile'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Bad credentials show inline login_error', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: <Override>[dioProvider.overrideWithValue(_instantDio())],
    );
    addTearDown(container.dispose);
    await _pumpApp(tester, container);

    // Valid email but a wrong password forces a 401.
    await tester.enterText(find.byType(TextField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('login_error')), findsOneWidget);
    // Still on the login screen.
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
  });
}
