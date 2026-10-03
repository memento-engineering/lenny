# leonard_contract

The pure-Dart extension contract for Leonard — the Flutter-free types a host
implements and exposes, so a Flutter binding (`leonard_flutter`) and a
non-Flutter VM-service host (`leonard_host`) build on identical contracts.

Contains:

- `LeonardExtension` / `LeonardTool` — the extension + tool authoring contract.
- `PerceptionExtension` — the observation mixin
  (`buildPerception() -> Component`), built on `genesis_perception`.
- `ExtensionRegistry` — extension lifecycle dispatch, the handshake manifest,
  and tool merging.
- `dispatchToolToEnvelope` / `decodeServiceExtensionParams` — VM-service
  dispatch helpers.

Perception is pull-free: `buildPerception()` is a **synchronous** read of state
kept current by an out-of-band watcher — never make it async.

```dart
class ExampleExtension extends LeonardExtension with PerceptionExtension {
  @override
  Component buildPerception() => const ExamplePerception();

  // Remaining LeonardExtension members omitted.
}
```

Extensions written against the deprecated Genesis `Seed` typedef remain
source-compatible because it is an identity-preserving alias for `Component`.
New code should use the canonical spelling.

Pre-1.0 and experimental; APIs may change before 1.0.
