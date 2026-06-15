/// The crux of spike 5: client-fired action message -> INTENT -> hit-test
/// against the LIVE mounted tree -> ENFORCE or REJECT (genesis A5:
/// "action validation == hit-testing").
///
/// The hit-test has three catalog/tree-derived gates, none hardcoded:
///   1. the target componentId resolves to a MOUNTED element in the live
///      tree (Surface.findById — walked fresh per route call);
///   2. the element's catalog type DECLARES the action name — looked up in
///      the generated, catalog-derived affordance data (actions.g.dart);
///   3. the payload validates (delegated to the target state).
/// Pass -> the intent is enforced via the target state's perceived(),
/// invalidating exactly the target subtree. Fail -> a structured
/// [Rejection]; the tree is untouched.
library;

import 'package:perception/perception.dart';

import 'src/actionable.dart';
import 'src/generated/actions.g.dart';
import 'surface.dart';

/// Client->server action message, modeled on the real A2UI v0.9 `action`
/// message (a2ui.org/specification/v0.9-a2ui/, fetched 2026-06-11): required
/// fields `name`, `surfaceId`, `sourceComponentId`, `timestamp` (ISO 8601),
/// `context` (object). See NOTES.md fidelity ledger for mirrored/diverged.
class ActionMessage {
  ActionMessage({
    required this.name,
    required this.surfaceId,
    required this.sourceComponentId,
    this.timestamp,
    this.context = const {},
  });

  /// Parses {"action": {...}} (envelope analog of the server->client
  /// message style; the v0.9 page does not show the client->server envelope
  /// — ledgered) or a bare action object.
  factory ActionMessage.fromJson(Map<String, Object?> json) {
    final actionRaw = json['action'];
    final body = actionRaw is Map ? actionRaw.cast<String, Object?>() : json;
    final name = body['name'];
    if (name is! String || name.isEmpty) {
      throw StateError('action "name" must be a non-empty string');
    }
    final surfaceId = body['surfaceId'];
    if (surfaceId is! String) {
      throw StateError('action "surfaceId" must be a string');
    }
    final sourceComponentId = body['sourceComponentId'];
    if (sourceComponentId is! String || sourceComponentId.isEmpty) {
      throw StateError(
        'action "sourceComponentId" must be a non-empty string',
      );
    }
    final contextRaw = body['context'];
    return ActionMessage(
      name: name,
      surfaceId: surfaceId,
      sourceComponentId: sourceComponentId,
      timestamp: body['timestamp'] as String?, // parsed leniently
      context: contextRaw == null
          ? const {}
          : (contextRaw as Map).cast<String, Object?>(),
    );
  }

  final String name;
  final String surfaceId;
  final String sourceComponentId;
  final String? timestamp;
  final Map<String, Object?> context;
}

sealed class RouteResult {}

/// The intent passed the hit-test and was ENFORCED via the target state's
/// perceived(), invalidating exactly the target subtree.
class Applied extends RouteResult {
  Applied({required this.componentId, required this.action, required this.change});

  final String componentId;
  final String action;

  /// What changed, e.g. {'count': {'from': 0, 'to': 1}}.
  final Map<String, Object?> change;

  @override
  String toString() => 'Applied($componentId.$action: $change)';
}

enum RejectionReason {
  /// The componentId has never appeared in any emission of this surface.
  unknownComponent,

  /// The componentId WAS valid in an earlier emission but is no longer
  /// mounted — the projection moved under the actor (agent async gap, A8).
  staleUnmounted,

  /// The component is live, but its catalog type does not declare this
  /// action name.
  undeclaredAction,

  /// Component and action are valid, but the message context/payload failed
  /// validation. No mutation was performed.
  badPayload,
}

/// Structured rejection: the intent failed the hit-test; the live tree was
/// left byte-for-byte untouched.
class Rejection extends RouteResult {
  Rejection({
    required this.componentId,
    required this.action,
    required this.reason,
    required this.detail,
  });

  final String componentId;
  final String action;
  final RejectionReason reason;
  final String detail;

  @override
  String toString() => 'Rejection(${reason.name}: $detail)';
}

class ActionRouter {
  ActionRouter(this.surface);

  final Surface surface;

  /// Routes a client action message back into the live tree as an intent.
  RouteResult route(ActionMessage msg) {
    Rejection reject(RejectionReason reason, String detail) => Rejection(
      componentId: msg.sourceComponentId,
      action: msg.name,
      reason: reason,
      detail: detail,
    );

    if (msg.surfaceId != surface.surfaceId) {
      return reject(
        RejectionReason.unknownComponent,
        'action targets surface "${msg.surfaceId}" but this surface is '
        '"${surface.surfaceId}"',
      );
    }

    // Gate 1: hit-test against the LIVE mounted tree.
    final element = surface.findById(msg.sourceComponentId);
    if (element == null) {
      if (surface.everSeenIds.contains(msg.sourceComponentId)) {
        return reject(
          RejectionReason.staleUnmounted,
          'component "${msg.sourceComponentId}" was present in an earlier '
          'emission of surface "${surface.surfaceId}" but is no longer '
          'mounted — the projection moved under the actor',
        );
      }
      return reject(
        RejectionReason.unknownComponent,
        'component "${msg.sourceComponentId}" has never existed in '
        'surface "${surface.surfaceId}"',
      );
    }
    assert(element.mounted, 'findById returned an unmounted element');

    // Gate 2: the catalog type of the LIVE element must declare the action.
    // Lookup goes through catalog-DERIVED generated data, never a hardcoded
    // set: actions.g.dart is projected from schema/catalog.json.
    final wireType = wireTypeOfPerception(element.perception);
    final declared = wireType == null ? null : componentActions[wireType];
    if (declared == null || !declared.containsKey(msg.name)) {
      return reject(
        RejectionReason.undeclaredAction,
        'component "${msg.sourceComponentId}" has catalog type '
        '"${wireType ?? element.perception.runtimeType}" which declares '
        'actions ${declared == null ? '(none)' : declared.keys.toList()}; '
        '"${msg.name}" is not among them',
      );
    }

    // Gate 3 + ENFORCE: dispatch the intent to the live state, which
    // validates the payload and mutates inside perceived().
    if (element is! StatefulElement || element.state is! ActionableState) {
      throw StateError(
        'catalog/code drift: catalog type "$wireType" declares actions but '
        'the mounted element (${element.runtimeType}) has no '
        'ActionableState to receive them',
      );
    }
    final outcome = (element.state as ActionableState).handleAction(
      msg.name,
      msg.context,
    );
    return switch (outcome) {
      HandledChange(:final change) => Applied(
        componentId: msg.sourceComponentId,
        action: msg.name,
        change: change,
      ),
      PayloadError(:final detail) => reject(
        RejectionReason.badPayload,
        detail,
      ),
    };
  }
}
