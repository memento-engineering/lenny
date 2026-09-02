/// Model-pair preflight for the `selfdrive` circuit.
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:http/http.dart' as http;

import 'selfdrive_circuit.dart';

/// Injectable source of model ids served by a gateway.
typedef ServedModelSource =
    Future<Set<String>> Function(Uri gatewayBase, String token);

/// Injectable environment lookup.
typedef EnvLookup = String? Function(String name);

/// Payload key carrying the one model id cleared for both harnesses.
const String kSelfdriveClearedModelKey = 'SELFDRIVE_MODEL_ID';

/// A preflight verdict.
sealed class PreflightVerdict {
  const PreflightVerdict();
}

/// Both requested ids are equal and served.
class PreflightCleared extends PreflightVerdict {
  /// Creates a cleared verdict.
  const PreflightCleared(this.modelId);

  /// The id pinned to both harnesses.
  final String modelId;
}

/// The model pair was refused.
class PreflightRefused extends PreflightVerdict {
  /// Creates a refusal.
  const PreflightRefused(this.message);

  /// A diagnostic naming both requested slots.
  final String message;
}

/// Judges a model pair against the served model catalog.
PreflightVerdict judgeSelfdriveModels({
  required String outerModelId,
  required String innerModelId,
  required Set<String> servedModelIds,
}) {
  final String outer = outerModelId.trim();
  final String inner = innerModelId.trim();
  final String pair =
      'outer=${outer.isEmpty ? 'absent' : outer} '
      'inner=${inner.isEmpty ? 'absent' : inner}';
  if (outer.isEmpty || inner.isEmpty) {
    return PreflightRefused(
      'selfdrive preflight refused: $pair — both '
      '$kSelfdriveOuterModelKey and $kSelfdriveInnerModelKey must be set',
    );
  }
  if (outer != inner) {
    return PreflightRefused(
      'selfdrive preflight refused: $pair — one name must pin both '
      'harnesses; two ids on one swift-infer server evict each other',
    );
  }
  if (!servedModelIds.contains(outer)) {
    final List<String> served = servedModelIds.toList()..sort();
    return PreflightRefused(
      'selfdrive preflight refused: $pair — $outer is not served by the '
      'gateway (served: ${served.isEmpty ? 'none' : served.join(',')})',
    );
  }
  return PreflightCleared(outer);
}

/// Reads the gateway's OpenAI-compatible `/v1/models` catalog.
Future<Set<String>> fetchServedModelIds(Uri gatewayBase, String token) async {
  final Uri url = gatewayBase.replace(
    path: '${gatewayBase.path.replaceAll(RegExp(r'/+$'), '')}/v1/models',
  );
  final http.Response response = await http.get(
    url,
    headers: <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
  );
  if (response.statusCode != 200) {
    throw StateError('$url returned HTTP ${response.statusCode}');
  }
  final Object? decoded = jsonDecode(response.body);
  final Object? data = decoded is Map ? decoded['data'] : null;
  if (data is! List) throw StateError('$url returned no `data` list');
  return <String>{
    for (final Object? entry in data)
      if (entry is Map && entry['id'] is String) entry['id'] as String,
  };
}

/// Refuses an invalid model pair before the process-bearing steps can launch.
class SelfdrivePreflightCapability extends ServiceCapability {
  /// Creates the capability over injected catalog and environment seams.
  const SelfdrivePreflightCapability({
    ServedModelSource models = fetchServedModelIds,
    EnvLookup env = _systemEnv,
  }) : _models = models,
       _env = env;

  static String? _systemEnv(String name) => io.Platform.environment[name];

  final ServedModelSource _models;
  final EnvLookup _env;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final Bead? bead = context.getInheritedSeedOfExactType<Bead>();
    final SelfdriveOrder? order = bead == null
        ? null
        : SelfdriveOrder.fromBead(bead);
    if (order == null) {
      return const Failed(
        'selfdrive preflight refused: the work bead carries no complete '
        'selfdrive order',
      );
    }
    final String endpoint = _env('SWIFT_INFER_ENDPOINT') ?? '';
    if (endpoint.isEmpty) {
      return const Failed(
        'selfdrive preflight refused: SWIFT_INFER_ENDPOINT is unset',
      );
    }
    final Set<String> served;
    try {
      served = await _models(
        Uri.parse(endpoint),
        _env('SWIFT_INFER_AGENT_TOKEN') ?? '',
      );
    } on Object catch (error) {
      return Failed(
        'selfdrive preflight refused: model catalog read failed: $error',
      );
    }
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final PreflightVerdict verdict = judgeSelfdriveModels(
      outerModelId: order.outerModelId,
      innerModelId: order.innerModelId,
      servedModelIds: served,
    );
    return switch (verdict) {
      PreflightCleared(:final String modelId) => Ok(<String, String>{
        kSelfdriveClearedModelKey: modelId,
      }),
      PreflightRefused(:final String message) => Failed(message),
    };
  }
}
