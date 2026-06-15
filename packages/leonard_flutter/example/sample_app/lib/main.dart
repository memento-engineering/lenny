import 'package:leonard_dio/leonard_dio.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_riverpod/leonard_riverpod.dart';
import 'package:leonard_router/leonard_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'services/api.dart';
import 'state/settings_provider.dart';

void main() => LeonardBinding.run(SampleApp());

class SampleApp implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) {
    // Riverpod observer must be installed on the SAME container the
    // RiverpodLeonardExtension sees and the SAME container the widget
    // tree consumes.
    final LeonardProviderObserver observer = LeonardProviderObserver();
    final ProviderContainer container = ProviderContainer(
      observers: <ProviderObserver>[observer],
    );

    // Materialize Dio + Router from the shared container so the plugins
    // observe the exact instances the app uses (PRD §7).
    final dio = container.read(dioProvider);
    final router = buildRouter(container);

    return LeonardAppConfig(
      plugins: <LeonardExtension>[
        RouterExtension(
          navigatorKey: rootNavigatorKey,
          routerDelegate: router.routerDelegate,
          // go_router uses the Router API (no Navigator.onGenerateRoute), so
          // drive navigation via goNamed — matching the app's own
          // context.go(...) — instead of Navigator-1.0 pushNamed (lenny-18q).
          navigate: (String name, Map<String, Object?>? args) async =>
              router.goNamed(name, extra: args),
        ),
        RiverpodLeonardExtension(container: container, observer: observer),
        LeonardDioExtension(dio),
      ],
      app: UncontrolledProviderScope(
        container: container,
        child: _SampleAppRoot(router: router),
      ),
    );
  }
}

/// ConsumerWidget so [MaterialApp.router] rebuilds with the live
/// `themeMode` whenever `settingsProvider.theme` changes.
class _SampleAppRoot extends ConsumerWidget {
  const _SampleAppRoot({required this.router});

  final RouterConfig<Object> router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode =
        ref.watch(settingsProvider.select((s) => s.theme));
    return MaterialApp.router(
      title: 'Sample App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
