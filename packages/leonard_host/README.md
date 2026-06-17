# leonard_host

A pure-Dart VM-service host for Leonard. `ExplorationHost` exposes a set of
`leonard_contract` extensions over the same `ext.exploration.*` VM-service
surface the Flutter binding hosts — minus the Flutter-only core fragment
(semantics / routes / screenshot) — so a non-Flutter Dart program can be
perceived and driven live by `leonard_cli` / `leonard_drive`.

```dart
final host = ExplorationHost(extensions: [MyExtension()]);
await host.install(); // registers ext.exploration.core.handshake,
                      // core.get_stable_observation, and a per-tool extension.
```

Run the hosting program with the VM service enabled (e.g.
`dart run --enable-vm-service`); the driver connects to the printed `ws://…/ws`.

Pre-1.0 and experimental; APIs may change before 1.0.
