import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/src/core_tools/dispatch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('core.system_back with nothing to pop never calls SystemNavigator.pop '
      '(lenny-ssviv)', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          calls.add(call);
          return null;
        });
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool sb = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'system_back',
    );
    final ToolResult r = await sb.call(const <String, Object?>{});
    expect(r.ok, isTrue, reason: r.error);
    expect(r.value, <String, Object?>{'handled': false, 'popped': false});
    expect(
      calls.where((MethodCall c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    cap.dispose();
  });

  test('core.system_back carries its result into the next turn', () {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final CoreTool sb =
        plugin.tools.firstWhere((LeonardTool t) => t.name == 'system_back')
            as CoreTool;
    expect(sb.carryForward, isTrue);
    cap.dispose();
  });
}
