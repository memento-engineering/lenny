import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'gauntlet/gauntlet_index_screen.dart';
import 'gauntlet/scenarios/async_reveal_screen.dart';
import 'gauntlet/scenarios/chart_read_screen.dart';
import 'gauntlet/scenarios/count_spatial_screen.dart';
import 'gauntlet/scenarios/custom_paint_control_screen.dart';
import 'gauntlet/scenarios/debounced_search_screen.dart';
import 'gauntlet/scenarios/decorative_motion_screen.dart';
import 'gauntlet/scenarios/expand_to_reach_screen.dart';
import 'gauntlet/scenarios/label_lie_screen.dart';
import 'gauntlet/scenarios/lazy_offscreen_screen.dart';
import 'gauntlet/scenarios/modal_trap_screen.dart';
import 'gauntlet/scenarios/object_id_screen.dart';
import 'gauntlet/scenarios/ocr_price_screen.dart';
import 'gauntlet/scenarios/optimistic_revert_screen.dart';
import 'gauntlet/scenarios/semantics_lie_screen.dart';
import 'gauntlet/scenarios/slider_semantic_value_screen.dart';
import 'gauntlet/scenarios/staggered_list_screen.dart';
import 'gauntlet/scenarios/transient_toast_screen.dart';
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
      GoRoute(
        path: '/g/settle/async-reveal',
        name: 'g-async-reveal',
        builder: (_, __) => const AsyncRevealScreen(),
      ),
      GoRoute(
        path: '/g/settle/optimistic-revert',
        name: 'g-optimistic-revert',
        builder: (_, __) => const OptimisticRevertScreen(),
      ),
      GoRoute(
        path: '/g/settle/debounced-search',
        name: 'g-debounced-search',
        builder: (_, __) => const DebouncedSearchScreen(),
      ),
      GoRoute(
        path: '/g/settle/staggered-list',
        name: 'g-staggered-list',
        builder: (_, __) => const StaggeredListScreen(),
      ),
      GoRoute(
        path: '/g/settle/transient-toast',
        name: 'g-transient-toast',
        builder: (_, __) => const TransientToastScreen(),
      ),
      GoRoute(
        path: '/g/vision/object-id',
        name: 'g-object-id',
        builder: (_, __) => const ObjectIdScreen(),
      ),
      GoRoute(
        path: '/g/vision/chart-read',
        name: 'g-chart-read',
        builder: (_, __) => const ChartReadScreen(),
      ),
      GoRoute(
        path: '/g/vision/ocr-price',
        name: 'g-ocr-price',
        builder: (_, __) => const OcrPriceScreen(),
      ),
      GoRoute(
        path: '/g/vision/count-spatial',
        name: 'g-count-spatial',
        builder: (_, __) => const CountSpatialScreen(),
      ),
      GoRoute(
        path: '/g/vision/semantics-lie',
        name: 'g-semantics-lie',
        builder: (_, __) => const SemanticsLieScreen(),
      ),
      GoRoute(
        path: '/g/control/label-lie',
        name: 'g-label-lie',
        builder: (_, __) => const LabelLieScreen(),
      ),
      GoRoute(
        path: '/g/control/slider-semantic-value',
        name: 'g-slider-semantic-value',
        builder: (_, __) => const SliderSemanticValueScreen(),
      ),
      GoRoute(
        path: '/g/control/expand-to-reach',
        name: 'g-expand-to-reach',
        builder: (_, __) => const ExpandToReachScreen(),
      ),
      GoRoute(
        path: '/g/control/modal-trap',
        name: 'g-modal-trap',
        builder: (_, __) => const ModalTrapScreen(),
      ),
      GoRoute(
        path: '/g/control/lazy-offscreen',
        name: 'g-lazy-offscreen',
        builder: (_, __) => const LazyOffscreenScreen(),
      ),
      GoRoute(
        path: '/g/control/custom-paint-control',
        name: 'g-custom-paint-control',
        builder: (_, __) => const CustomPaintControlScreen(),
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
