import 'package:flutter/widgets.dart';

import '../../contract/types.dart';
import '../core_extension.dart';
import '../dispatch.dart';

/// `core.system_back` — a platform back press that never exits the app.
///
/// The press is dispatched the way the engine delivers a real one: through
/// [WidgetsBinding.handlePopRoute] (what the binding runs for an engine
/// `popRoute` on `flutter/navigation`), which offers it to each registered
/// [WidgetsBindingObserver] in turn (the `WidgetsApp` root navigator, a
/// `Router`'s `RootBackButtonDispatcher`, any custom observer) until one
/// handles it. A pushed route pops; a `PopScope(canPop: false)` route or a
/// `LocalHistoryRoute` (an open drawer) consumes the press without leaving.
///
/// What it never does is quit. When no observer handles the press — the app
/// is at its root — [WidgetsBinding.handlePopRoute] would fall back to
/// `SystemNavigator.pop`, which exits the app (lenny-ssviv: a model's back
/// at the macOS sample's Home route collected the isolate and ended the run).
/// A sentinel observer registered for the duration of the call, last in the
/// binding's observer order (`addObserver` appends; `handlePopRoute` walks a
/// snapshot in order and stops at the first `true`), absorbs that unhandled
/// press instead, so the fallback is unreachable.
///
/// The result value (carried forward to the next model turn) reports:
/// - `handled` — some observer consumed the press (a route popped, or a
///   `PopScope` / drawer / back-button dispatcher took it);
/// - `popped` — a route that was on top of a navigator left the stack.
///
/// At the root both are `false` and the result is still `ok`: a back with
/// nothing to pop is a valid action with no effect, not a failure.
class SystemBackTool extends CoreTool {
  SystemBackTool(super.plugin);

  @override
  String get name => 'system_back';

  @override
  String get description =>
      'Press the platform back button: pops the top route (or lets a '
      'PopScope/drawer handle it). Never exits the app — at the root it does '
      'nothing. Result: {handled, popped}; popped=false means no route left.';

  /// The `{handled, popped}` flags are the model's only signal that a back
  /// at the root did nothing, so they ride into the next turn.
  @override
  bool get carryForward => true;

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    try {
      final WidgetsBinding binding = WidgetsBinding.instance;
      final List<Route<dynamic>> topRoutes = _topRoutes(binding.rootElement);
      final _UnhandledBackSentinel sentinel = _UnhandledBackSentinel();
      binding.addObserver(sentinel);
      try {
        // The sentinel always returns true, so handlePopRoute never reaches
        // its SystemNavigator.pop fallback.
        //
        // handlePopRoute is the method the binding's own `flutter/navigation`
        // handler calls for an engine `popRoute`, so this is the real back
        // path. It is annotated @protected/@visibleForTesting; the public
        // alternative (pushing a `popRoute` message through channelBuffers)
        // runs the handler in the binding's zone and deadlocks under
        // testWidgets' fake async, which would break every widget-test
        // consumer that drives this tool (e.g. leonard_flutter_test).
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        await binding.handlePopRoute();
      } finally {
        binding.removeObserver(sentinel);
      }
      final bool popped = topRoutes.any((Route<dynamic> r) => !r.isActive);
      return ToolResult(
        ok: true,
        value: <String, Object?>{
          'handled': !sentinel.reached,
          'popped': popped,
        },
      );
    } catch (e) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.systemBackFailed}: $e',
      );
    }
  }

  /// The top present route of every [NavigatorState] mounted under [root]
  /// (nested navigators included), captured before the press so [call] can
  /// tell whether one of them left the stack.
  static List<Route<dynamic>> _topRoutes(Element? root) {
    final List<Route<dynamic>> out = <Route<dynamic>>[];
    void visit(Element e) {
      if (e is StatefulElement && e.state is NavigatorState) {
        // NavigatorState exposes no top-route getter; a popUntil whose
        // predicate accepts the first route it is offered pops nothing and
        // hands us the top present route.
        (e.state as NavigatorState).popUntil((Route<dynamic> r) {
          out.add(r);
          return true;
        });
      }
      e.visitChildren(visit);
    }

    if (root != null) visit(root);
    return out;
  }
}

/// Registered last for one [SystemBackTool.call]: reached only when no app
/// observer handled the back press, and claims it so
/// [WidgetsBinding.handlePopRoute] never falls back to `SystemNavigator.pop`.
class _UnhandledBackSentinel with WidgetsBindingObserver {
  bool reached = false;

  @override
  Future<bool> didPopRoute() async {
    reached = true;
    return true;
  }
}
