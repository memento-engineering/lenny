import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('core.system_back invokes SystemNavigator.pop and returns ok',
      () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      calls.add(call);
      return null;
    });
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool sb = plugin.tools
        .firstWhere((ExplorationTool t) => t.name == 'system_back');
    final ToolResult r = await sb.call(const <String, Object?>{});
    expect(r.ok, isTrue, reason: r.error);
    expect(calls, hasLength(1));
    expect(calls.first.method, 'SystemNavigator.pop');
    cap.dispose();
  });

  test('core.system_back returns system_back_failed on platform throw',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      throw PlatformException(code: 'BOOM');
    });
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool sb = plugin.tools
        .firstWhere((ExplorationTool t) => t.name == 'system_back');
    final ToolResult r = await sb.call(const <String, Object?>{});
    expect(r.ok, isFalse);
    expect(r.error, contains('system_back_failed'));
    cap.dispose();
  });
}
