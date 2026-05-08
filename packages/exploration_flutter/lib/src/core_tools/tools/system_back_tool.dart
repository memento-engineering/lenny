import 'package:flutter/services.dart';

import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';

/// `core.system_back` — dispatches a back-navigation via
/// `SystemNavigator.pop`.
class SystemBackTool extends CoreTool {
  SystemBackTool(super.plugin);

  @override
  String get name => 'system_back';

  @override
  String get description =>
      'Dispatch a back-navigation via SystemNavigator.pop.';

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
      await SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
      return const ToolResult(ok: true, value: <String, Object?>{});
    } catch (e) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.systemBackFailed}: $e',
      );
    }
  }
}
