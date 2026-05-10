import 'package:exploration_dio/exploration_dio.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:exploration_riverpod/exploration_riverpod.dart';
import 'package:exploration_router/exploration_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'services/api.dart';
import 'state/settings_provider.dart';

void main() => ExplorationBinding.run(SampleApp());

class SampleApp implements ExplorationApp {
  @override
  ExplorationAppConfig build(ExplorationAppContext ctx) {
    // Riverpod observer must be installed on the SAME container the
    // RiverpodExplorationPlugin sees and the SAME container the widget
    // tree consumes.
    final ExplorationProviderObserver observer = ExplorationProviderObserver();
    final ProviderContainer container = ProviderContainer(
      observers: <ProviderObserver>[observer],
    );

    // Materialize Dio + Router from the shared container so the plugins
    // observe the exact instances the app uses (PRD §7).
    final dio = container.read(dioProvider);
    final router = buildRouter(container);

    return ExplorationAppConfig(
      plugins: <ExplorationPlugin>[
        RouterPlugin(
          navigatorKey: rootNavigatorKey,
          routerDelegate: router.routerDelegate,
        ),
        RiverpodExplorationPlugin(container: container, observer: observer),
        ExplorationDioPlugin(dio),
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
