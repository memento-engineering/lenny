/// Tool-call counting [LoopHost] adapter for the dogfood harness
/// (bead lenny-cx6.43).
///
/// Wraps any [LoopHost] and increments a counter on every successful
/// [executeAction]. The harness wires this around a [DefaultLoopHost]
/// so [DogfoodRunResult.toolCallCount] is exact rather than estimated
/// from trajectory inspection.
library;

import '../loop_driver/loop_host.dart';
import '../observation/models.dart';
import '../provider/types.dart';

/// Decorator over a [LoopHost] that counts validated tool calls.
///
/// Failures inside the wrapped [executeAction] propagate; the counter
/// only increments on successful returns. All other [LoopHost] methods
/// are forwarded verbatim.
class CountingLoopHost implements LoopHost {
  CountingLoopHost(this._inner);

  final LoopHost _inner;
  int _count = 0;

  /// Cumulative number of successful tool calls dispatched through
  /// [executeAction] since construction.
  int get toolCallCount => _count;

  @override
  Future<Observation> observe() => _inner.observe();

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    final Map<String, dynamic> r = await _inner.executeAction(tool, args);
    _count++;
    return r;
  }

  @override
  Future<void> notifyPlugins(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) =>
      _inner.notifyPlugins(tool, args, result);

  @override
  void disablePlugin(String namespace, String reason) =>
      _inner.disablePlugin(namespace, reason);

  @override
  List<ToolDescriptor> mergedTools() => _inner.mergedTools();

  @override
  Set<String> activePluginNamespaces() => _inner.activePluginNamespaces();

  @override
  String get agentsMd => _inner.agentsMd;

  @override
  String get goal => _inner.goal;
}
