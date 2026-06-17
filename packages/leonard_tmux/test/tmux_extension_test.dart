import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_tmux/leonard_tmux.dart';
import 'package:test/test.dart';

/// The genesis_tmux `-F` field delimiter (U+241E).
const String fs = '␞';

TmuxClient _client(FakeTmuxExecutor fake) => TmuxClient(
  executor: fake,
  socket: const TmuxSocket.named('s'),
  version: v3_6,
);

/// A fake answering list-sessions / list-panes / capture-pane with one
/// session and one live pane, so [gatherTmuxObservation] yields a snapshot.
FakeTmuxExecutor _populatedFake() => FakeTmuxExecutor()
  ..handler = (a) {
    if (a.contains('list-sessions')) {
      return FakeTmuxExecutor.ok('\$0${fs}demo${fs}0${fs}1\n');
    }
    if (a.contains('list-panes')) {
      return FakeTmuxExecutor.ok('%0$fs@0${fs}1234${fs}1${fs}0$fs${fs}bash\n');
    }
    if (a.contains('capture-pane')) {
      return FakeTmuxExecutor.ok('hello\nworld\n');
    }
    return null; // everything else: default success
  };

Map<String, Object?> _fragment(TmuxExtension ext) {
  final owner = PerceptionOwner();
  final root = owner.mountRoot(ext.buildPerception());
  final data = serializePerceptionFragment(root);
  owner.unmountRoot();
  return data;
}

void main() {
  test('exposes bare-token contract tools (registry adds the namespace)', () {
    final ext = TmuxExtension(_client(FakeTmuxExecutor()));
    expect(ext.namespace, 'tmux');
    expect(
      ext.tools.map((t) => t.name),
      containsAll(<String>['send_keys', 'new_session']),
    );
    final sendKeys = ext.tools.firstWhere((t) => t.name == 'send_keys');
    expect(sendKeys.inputSchema.raw['required'], <String>['pane', 'text']);
  });

  test('idle before initialize; stateful perception after', () async {
    final ext = TmuxExtension(_client(_populatedFake()));
    expect(ext.isPerceptionIdle(), isTrue);

    await ext.initialize(ExtensionContext(namespace: 'tmux'));
    addTearDown(ext.dispose);

    expect(ext.isPerceptionIdle(), isFalse);
    final data = _fragment(ext);
    expect(data['socket'], '-L s');
    expect(data['session_count'], 1);
    expect(data['pane_count'], 1);
    final panes = data['panes']! as Map<String, dynamic>;
    expect(panes['%0'], containsPair('command', 'bash'));
    expect(panes['%0'], containsPair('recent_output', 'hello\nworld'));
  });

  test('send_keys tool dispatches a literal send to the client verb', () async {
    final fake = _populatedFake();
    final ext = TmuxExtension(_client(fake));
    await ext.initialize(ExtensionContext(namespace: 'tmux'));
    addTearDown(ext.dispose);

    final tool = ext.tools.firstWhere((t) => t.name == 'send_keys');
    final res = await tool.call(<String, Object?>{
      'pane': '%0',
      'text': 'echo hi',
    });
    expect(res.ok, isTrue);
    expect((res.value! as Map)['pane'], '%0');
    expect(
      fake.calls.any((c) => c.contains('-l') && c.contains('echo hi')),
      isTrue,
    );
  });

  test('send_keys with missing args is a structured error, not a throw',
      () async {
    final ext = TmuxExtension(_client(_populatedFake()));
    await ext.initialize(ExtensionContext(namespace: 'tmux'));
    addTearDown(ext.dispose);

    final tool = ext.tools.firstWhere((t) => t.name == 'send_keys');
    final res = await tool.call(const <String, Object?>{'pane': '%0'});
    expect(res.ok, isFalse);
    expect(res.error, isNotNull);
  });
}
