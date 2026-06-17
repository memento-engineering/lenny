library;

/// A synchronous snapshot bridge between imperative host state (Navigator,
/// RouterDelegate, …) and a perception build.
///
/// dio's `DioPerception` can read a plain Dart model (the interceptor) directly,
/// so it needs no anchor. The router's fragment is computed from Flutter's
/// Navigator/RouterDelegate — imperative widget-tree state, not a plain model.
/// A [PerceptionAnchor] is the tiny adapter that captures a synchronous
/// SNAPSHOT of that state at observation time and feeds it into the perception
/// build.
abstract class PerceptionAnchor<T> {
  /// Reads a synchronous snapshot of the underlying imperative state.
  T read();
}

/// Value-type snapshot of route state — the exact triple the router
/// observation fragment carries.
class RouteSnapshot {
  /// Creates a route snapshot.
  const RouteSnapshot({
    required this.currentRouteName,
    required this.stack,
    required this.arguments,
  });

  /// The name of the top route, or null when no named route is present.
  final String? currentRouteName;

  /// The route names from bottom to top of the navigation stack.
  final List<String> stack;

  /// The arguments of the top route, or null when it has no Map arguments.
  final Map<String, Object?>? arguments;
}
