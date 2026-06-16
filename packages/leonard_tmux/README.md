# leonard_tmux

A **pure-Dart, process-backed Leonard extension** for tmux — the first `leonard_*`
extension that observes an *external process* instead of the host Flutter app, so
it pulls in no Flutter.

It does the two things a Leonard extension does, in Leonard's pure-Dart
vocabulary (`leonard_agent`):

- **Observe** — gathers a `genesis_tmux` client's sessions, panes, and recent
  output, projects them into a `genesis_perception` `Node`/`Field` tree
  (`TmuxPerception`), and serializes that into an `ExtensionFragment` under the
  `tmux` namespace.
- **Act** — contributes `tmux.send_keys` / `tmux.new_session` `ToolDescriptor`s,
  dispatched by `executeAction` to the underlying tmux verbs.

```dart
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_tmux/leonard_tmux.dart';

final client = TmuxClient(
  executor: const ProcessTmuxExecutor(),
  socket: const TmuxSocket.named('leonard'),
);
final tmux = TmuxExtension(client);

await tmux.executeAction('tmux.new_session', {'name': 'agent'});
final fragment = await tmux.observe();   // ExtensionFragment(namespace: 'tmux', …)
print(fragment.toJson());                // sessions / panes / recent_output
```

## Dependency wiring

`genesis_tmux` is not yet published, so the lenny workspace resolves it through a
sibling-checkout **path override** in the root `pubspec.yaml`:

```yaml
dependency_overrides:
  genesis_tmux:
    path: ../../engineering.memento/genesis/packages/tmux
```

`genesis_perception` is consumed hosted (`^0.1.1`), like the other extensions.
Flip `genesis_tmux` to a hosted constraint once it publishes.

## Live example

`example/main.dart` proves the whole path against a real tmux server on an
isolated `-L` socket (self-skips if tmux is absent, and kills its own server on
exit):

```bash
cd packages/leonard_tmux
dart run example/main.dart
```

It creates a session, prints the projected observation, sends `echo` through the
`tmux.send_keys` tool, and prints the observation again — the `recent_output`
field shows the change.

> Pre-1.0 and experimental; APIs may change before 1.0.
