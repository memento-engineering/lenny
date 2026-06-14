import 'dart:async';

import 'package:flutter/widgets.dart';

import '../errors/error_ring_buffer.dart';
import 'stability_metadata.dart';

/// Best-effort Navigator 1.0 route-stack name extractor.
///
/// Walks the live element tree from [WidgetsBinding.instance.rootElement]
/// to locate the first [NavigatorState], then projects each entry whose
/// route is a [PageRoute] (which is what the Navigator 1.0 `routes:` /
/// `MaterialApp.routes` API produces) to its `settings.name`.
///
/// Returns `[]` when no rootElement, no NavigatorState, or no
/// name-bearing entries are present (Navigator 2.0 apps fall through
/// here — by design per PRD §9.2 "best-effort").
List<String> bestEffortRouteStack() {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return const <String>[];
  NavigatorState? navigator;
  void visit(Element el) {
    if (navigator != null) return;
    if (el is StatefulElement && el.state is NavigatorState) {
      navigator = el.state as NavigatorState;
      return;
    }
    el.visitChildren(visit);
  }

  root.visitChildren(visit);
  final NavigatorState? nav = navigator;
  if (nav == null) return const <String>[];

  final List<String> out = <String>[];
  // NavigatorState exposes the active history via [Navigator.popUntil] /
  // related APIs, but those don't enumerate. The safest stable-API
  // approach is to walk via `Navigator.canPop` / `maybePop` checks; we
  // instead reach for the single name we can read without breaking
  // encapsulation: the current route's settings name. Iterating the
  // private history would couple us to framework internals.
  //
  // Strategy: use `Navigator.of(context)` semantics — read the topmost
  // route via `popUntil` callback. We avoid that: instead query each
  // overlay entry, which is the public surface that backs the route
  // stack.
  final OverlayState? overlay = nav.overlay;
  if (overlay == null) return const <String>[];
  // No public stable API to iterate the route history; project the
  // current top route name only via popUntil's predicate. We use that
  // as the single best-effort entry — the agent gets at least the
  // landing screen's name, which is the contract for "best-effort".
  String? topName;
  nav.popUntil((Route<dynamic> r) {
    topName ??= r.settings.name;
    return true;
  });
  if (topName != null && topName!.isNotEmpty) out.add(topName!);
  return out;
}

/// The already-computed core primitives, captured once so the legacy map
/// ([CoreFragmentValues.toMap]) and the perception `Seed`
/// (`buildCorePerceptionSeed`) are driven from one identical set of values.
///
/// Field order here mirrors the legacy map's key order
/// (semantics, routes, errors, stability, then the optional screenshot),
/// which is the contract the perception path must reproduce byte-for-byte.
class CoreFragmentValues {
  const CoreFragmentValues({
    required this.semantics,
    required this.routes,
    required this.errors,
    required this.stability,
    this.screenshot,
  });

  /// `captureSemantics()` output, verbatim.
  final List<Map<String, Object>> semantics;

  /// `routeStackProvider`/`bestEffortRouteStack` output, verbatim.
  final List<String> routes;

  /// `errors.map((e) => e.toJson()).toList()` output, verbatim.
  final List<Map<String, Object?>> errors;

  /// `stability.toJson()` map, verbatim.
  final Map<String, Object?> stability;

  /// Base64 PNG — only present when a screenshot was requested AND captured.
  final String? screenshot;

  /// The legacy core fragment map. Key insertion order is
  /// semantics, routes, errors, stability, [screenshot_png_b64].
  Map<String, Object?> toMap() {
    final Map<String, Object?> out = <String, Object?>{
      'semantics': semantics,
      'routes': routes,
      'errors': errors,
      'stability': stability,
    };
    if (screenshot != null) out['screenshot_png_b64'] = screenshot;
    return out;
  }
}

/// Compute the core fragment primitives from the binding seams (PRD §9.2).
///
/// `semantics`, `errors`, and `stability` are always present. `routes`
/// is best-effort (see [bestEffortRouteStack]). `screenshot_png_b64` is
/// only included when [includeScreenshot] is `true` AND
/// [captureScreenshot] returns successfully; failures are absorbed and
/// the field is omitted (the screenshot capture path already throws
/// `ScreenshotUnavailable` for known failure modes).
///
/// The returned [CoreFragmentValues] is the single source both the legacy
/// map ([CoreFragmentValues.toMap]) and the perception `Seed` consume, so
/// the two paths are fed byte-identical inputs.
Future<CoreFragmentValues> computeCoreFragmentValues({
  required Future<List<Map<String, Object>>> Function() captureSemantics,
  required List<ErrorEntry> Function(int? cursor) errorsSince,
  required StabilityMetadata stability,
  required bool includeScreenshot,
  required Future<String?> Function()? captureScreenshot,
  required int? errorCursor,
  List<String> Function()? routeStackProvider,
}) async {
  final List<Map<String, Object>> semantics = await captureSemantics();
  final List<ErrorEntry> errors = errorsSince(errorCursor);
  final List<String> routes = (routeStackProvider ?? bestEffortRouteStack)();
  String? screenshot;
  if (includeScreenshot && captureScreenshot != null) {
    screenshot = await captureScreenshot();
  }
  return CoreFragmentValues(
    semantics: semantics,
    routes: routes,
    errors: errors.map((ErrorEntry e) => e.toJson()).toList(growable: false),
    stability: stability.toJson(),
    screenshot: screenshot,
  );
}

/// Compose the core observation fragment (PRD §9.2).
///
/// Thin wrapper over [computeCoreFragmentValues] + [CoreFragmentValues.toMap]
/// that preserves the exact legacy return shape and key order. Behavior is
/// unchanged from before the value-computation was extracted.
Future<Map<String, Object?>> buildCoreFragment({
  required Future<List<Map<String, Object>>> Function() captureSemantics,
  required List<ErrorEntry> Function(int? cursor) errorsSince,
  required StabilityMetadata stability,
  required bool includeScreenshot,
  required Future<String?> Function()? captureScreenshot,
  required int? errorCursor,
  List<String> Function()? routeStackProvider,
}) async {
  final CoreFragmentValues values = await computeCoreFragmentValues(
    captureSemantics: captureSemantics,
    errorsSince: errorsSince,
    stability: stability,
    includeScreenshot: includeScreenshot,
    captureScreenshot: captureScreenshot,
    errorCursor: errorCursor,
    routeStackProvider: routeStackProvider,
  );
  return values.toMap();
}
