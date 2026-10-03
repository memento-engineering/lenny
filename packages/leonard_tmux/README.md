# leonard_tmux

A **pure-Dart, process-backed Leonard extension** for tmux — the first `leonard_*`
extension that observes an *external process* instead of the host Flutter app, so
it pulls in no Flutter.

It does the two things a Leonard extension does through `leonard_contract`:

- **Perceive** — `initialize()` starts a poll watcher that keeps a cached
  `TmuxObservation` current. Synchronous `buildPerception()` projects that
  cache into a Genesis `Component` tree under the `tmux` namespace.
- **Act** — contributes `tmux.send_keys` and `tmux.new_session` tools. Each
  tool drives the underlying tmux verb and refreshes the cache afterward.

```dart
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_tmux/leonard_tmux.dart';

final client = TmuxClient(
  executor: const ProcessTmuxExecutor(),
  socket: const TmuxSocket.named('leonard'),
);
final tmux = TmuxExtension(client);

await tmux.initialize(ExtensionContext(namespace: 'tmux'));
final create = tmux.tools.firstWhere((tool) => tool.name == 'new_session');
await create.call({'name': 'agent'});

final owner = PerceptionOwner();
final Element root = owner.mountRoot(tmux.buildPerception());
final fragment = serializePerceptionFragment(root);
owner.dispose();
print(fragment); // sessions / panes / recent_output
```

## Dependency wiring

Both Genesis dependencies are hosted releases. Extension packages should use
`genesis_perception: ^0.4.0-dev.1` and avoid committed path overrides.

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
