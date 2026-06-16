import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'gauntlet/gauntlet_index_screen.dart';
import 'gauntlet/scenarios/decorative_motion_screen.dart';
import 'screens/change_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/items_list_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terms_screen.dart';
import 'state/auth_provider.dart';

/// Root navigator key shared with the Exploration Router extension so the
/// agent observes the same Navigator stack the app drives.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Builds the app's [GoRouter] with an auth-guard redirect.
///
/// [container] is the same [ProviderContainer] mounted by the
/// [UncontrolledProviderScope] in main.dart so the redirect reads the
/// live auth state.
GoRouter buildRouter(ProviderContainer container) {
  // Notify GoRouter when auth toggles so redirect re-evaluates.
  final authListenable = _AuthListenable(container);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: authListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final loggedIn = container.read(authProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/home';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (_, __) => const ChangeProfileScreen(),
      ),
      GoRoute(
        path: '/items',
        name: 'items',
        builder: (_, __) => const ItemsListScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/terms',
        name: 'terms',
        builder: (_, __) => const TermsScreen(),
      ),
      // ── Gauntlet: real-world pitfall fixtures (lenny-7s4t) ───────────
      GoRoute(
        path: '/gauntlet',
        name: 'gauntlet',
        builder: (_, __) => const GauntletIndexScreen(),
      ),
      GoRoute(
        path: '/g/settle/decorative-motion',
        name: 'g-decorative-motion',
        builder: (_, __) => const DecorativeMotionScreen(),
      ),
    ],
  );
}

/// Bridges Riverpod's [authProvider] into a [Listenable] GoRouter can
/// subscribe to via [GoRouter.refreshListenable].
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._container) {
    _sub = _container.listen<String?>(
      authProvider,
      (_, __) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final ProviderContainer _container;
  late final ProviderSubscription<String?> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
