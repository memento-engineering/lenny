# leonard_contract

The pure-Dart extension contract for Leonard — the Flutter-free types a host
implements and exposes, so a Flutter binding (`leonard_flutter`) and a
non-Flutter VM-service host (`leonard_host`) build on identical contracts.

Contains:

- `LeonardExtension` / `LeonardTool` — the extension + tool authoring contract.
- `PerceptionExtension` — the observation mixin (`buildPerception() -> Seed`),
  built on `genesis_perception`.
- `ExtensionRegistry` — extension lifecycle dispatch, the handshake manifest,
  and tool merging.
- `dispatchToolToEnvelope` / `decodeServiceExtensionParams` — VM-service
  dispatch helpers.

Perception is pull-free: `buildPerception()` is a **synchronous** read of state
kept current by an out-of-band watcher (genesis ADR-0006) — never make it async.

Pre-1.0 and experimental; APIs may change before 1.0.
