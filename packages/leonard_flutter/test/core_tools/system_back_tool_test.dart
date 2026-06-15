import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('core.system_back invokes SystemNavigator.pop and returns ok', () async {
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
    expect(calls, hasLength(1));
    expect(calls.first.method, 'SystemNavigator.pop');
    cap.dispose();
  });

  test(
    'core.system_back returns system_back_failed on platform throw',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            throw PlatformException(code: 'BOOM');
          });
      final SemanticsCapture cap = SemanticsCapture();
      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool sb = plugin.tools.firstWhere(
        (LeonardTool t) => t.name == 'system_back',
      );
      final ToolResult r = await sb.call(const <String, Object?>{});
      expect(r.ok, isFalse);
      expect(r.error, contains('system_back_failed'));
      cap.dispose();
    },
  );
}
