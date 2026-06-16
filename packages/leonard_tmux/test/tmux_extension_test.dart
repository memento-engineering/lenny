import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_tmux/leonard_tmux.dart';
import 'package:test/test.dart';

/// The genesis_tmux `-F` field delimiter (U+241E).
const String fs = '␞';

TmuxClient _client(FakeTmuxExecutor fake) => TmuxClient(
  executor: fake,
  socket: const TmuxSocket.named('s'),
  version: v3_6,
);

void main() {
  group('observe() projection', () {
    test(
      'projects sessions/panes/output into a tmux ExtensionFragment',
      () async {
        final fake = FakeTmuxExecutor()
          ..handler = (a) {
            if (a.contains('list-sessions')) {
              return FakeTmuxExecutor.ok('\$0${fs}demo${fs}0${fs}1\n');
            }
            if (a.contains('list-panes')) {
              return FakeTmuxExecutor.ok(
                '%0$fs@0${fs}1234${fs}1${fs}0$fs${fs}bash\n',
              );
            }
            if (a.contains('capture-pane')) {
              return FakeTmuxExecutor.ok('hello\nworld\n');
            }
            return null;
          };

        final fragment = await TmuxExtension(_client(fake)).observe();

        expect(fragment.namespace, 'tmux');
        expect(fragment.deltaFriendly, isTrue);

        final data = fragment.data;
        expect(data['socket'], '-L s');
        expect(data['session_count'], 1);
        expect(data['pane_count'], 1);

        final sessions = data['sessions'] as Map<String, dynamic>;
        expect(sessions['demo'], {
          'id': '\$0',
          'attached': false,
          'windows': 1,
        });

        final panes = data['panes'] as Map<String, dynamic>;
        expect(panes['%0'], {
          'window': '@0',
          'command': 'bash',
          'pid': 1234,
          'dead': false,
          'recent_output': 'hello\nworld',
        });
      },
    );

    test('toJson wraps the fragment in the namespace envelope', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) =>
            a.contains('capture-pane') ? FakeTmuxExecutor.ok('') : null;
      final json = (await TmuxExtension(_client(fake)).observe()).toJson();
      expect(json['namespace'], 'tmux');
      expect(json['delta_friendly'], isTrue);
      expect(json['data'], isA<Map<String, dynamic>>());
    });
  });

  group('tools / executeAction', () {
    test('exposes namespaced tool descriptors', () {
      final tools = TmuxExtension(_client(FakeTmuxExecutor())).tools;
      expect(
        tools.map((t) => t.name),
        containsAll(['tmux.send_keys', 'tmux.new_session']),
      );
      final sendKeys = tools.firstWhere((t) => t.name == 'tmux.send_keys');
      expect(sendKeys.inputSchema['required'], ['pane', 'text']);
    });

    test('tmux.send_keys dispatches a literal send to the pane', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) =>
            a.last == '#{pane_in_mode}' ? FakeTmuxExecutor.ok('0') : null;
      final result = await TmuxExtension(
        _client(fake),
      ).executeAction('tmux.send_keys', {'pane': '%1', 'text': 'echo hi'});
      expect(result, {'ok': true, 'pane': '%1'});
      expect(
        fake.calls.any((c) => c.contains('-l') && c.last == 'echo hi'),
        isTrue,
      );
    });

    test('tmux.new_session returns the created pane id', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) {
          if (a.contains('has-session')) {
            return FakeTmuxExecutor.fail("can't find session");
          }
          if (a.contains('new-session')) return FakeTmuxExecutor.ok('%5\n');
          return null;
        };
      final result = await TmuxExtension(
        _client(fake),
      ).executeAction('tmux.new_session', {'name': 'agent'});
      expect(result, {'ok': true, 'pane': '%5'});
    });

    test('an unknown tool is a structured error, not a throw', () async {
      final result = await TmuxExtension(
        _client(FakeTmuxExecutor()),
      ).executeAction('tmux.bogus', const {});
      expect(result['ok'], isFalse);
      expect(result['error'], contains('unknown tool'));
    });

    test('missing required args are a structured error', () async {
      final result = await TmuxExtension(
        _client(FakeTmuxExecutor()),
      ).executeAction('tmux.send_keys', const {'pane': '%0'});
      expect(result['ok'], isFalse);
    });
  });
}
