import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_cli/src/action_environment_loop_host.dart';
import 'package:test/test.dart';

void main() {
  test(
    'resolves exact placeholders only in delegated action arguments',
    () async {
      final _FakeLoopHost fake = _FakeLoopHost();
      final ActionEnvironmentLoopHost host = ActionEnvironmentLoopHost(
        delegate: fake,
        valuesByName: const <String, String>{
          'SWIFT_INFER_AGENT_TOKEN': 'runtime-secret',
          'SWIFT_INFER_ENDPOINT': 'https://swift.example',
        },
      );
      const Map<String, dynamic> original = <String, dynamic>{
        'text': r'${SWIFT_INFER_AGENT_TOKEN}',
        'nested': <Object?>[r'${SWIFT_INFER_ENDPOINT}', 'unchanged'],
      };

      await host.executeAction('core.enter_text', original);
      await host.notifyExtensions(
        'core.enter_text',
        original,
        const <String, dynamic>{'ok': true},
      );

      expect(fake.executedArgs, <String, dynamic>{
        'text': 'runtime-secret',
        'nested': <Object?>['https://swift.example', 'unchanged'],
      });
      expect(fake.notifiedArgs, fake.executedArgs);
      expect(original['text'], r'${SWIFT_INFER_AGENT_TOKEN}');
    },
  );

  test('leaves unknown and embedded placeholders unchanged', () async {
    final _FakeLoopHost fake = _FakeLoopHost();
    final ActionEnvironmentLoopHost host = ActionEnvironmentLoopHost(
      delegate: fake,
      valuesByName: const <String, String>{'KNOWN': 'resolved'},
    );

    await host.executeAction('core.enter_text', const <String, dynamic>{
      'unknown': r'${UNKNOWN}',
      'embedded': r'prefix-${KNOWN}',
    });

    expect(fake.executedArgs, <String, dynamic>{
      'unknown': r'${UNKNOWN}',
      'embedded': r'prefix-${KNOWN}',
    });
  });
}

class _FakeLoopHost implements LoopHost {
  Map<String, dynamic>? executedArgs;
  Map<String, dynamic>? notifiedArgs;

  @override
  String get agentsMd => 'agents';

  @override
  String get goal => 'goal';

  @override
  Set<String> activeExtensionNamespaces() => const <String>{};

  @override
  void disableExtension(String namespace, String reason) {}

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    executedArgs = args;
    return const <String, dynamic>{'ok': true};
  }

  @override
  List<ToolDescriptor> mergedTools() => const <ToolDescriptor>[];

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {
    notifiedArgs = args;
  }

  @override
  Future<Observation> observe() async => Observation.empty();
}
