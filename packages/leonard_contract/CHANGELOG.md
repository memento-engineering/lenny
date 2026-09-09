# Changelog

## 0.2.5

- Added: `ExtensionRegistry.handshakeManifest` — the schema-bearing manifest
  carrying each registered tool's device-owned description and raw input schema
  alongside the legacy bare-name list. `manifest` stays the names-only view and
  is unchanged, so every existing caller is unaffected (lenny#123).

## 0.2.4

- Added: tool dispatch carries a per-tool `carryForward` opt-in, so a tool's successful result is staged into the next turn only when the tool asks for it (`core.recall` does; `inspect_widget` and every other tool do not). Additive — existing dispatch call sites are unchanged (lenny#116).

## 0.2.3

- Registry strike handling is one directly testable counter instead of parallel
  failure and disable maps: `ExtensionRegistry` derives both its tripping and
  its diagnostic thresholds from a single policy. Internal only — the counter is
  not exported and `ExtensionRegistry`'s surface is unchanged.

## 0.2.2

- Bump `genesis_perception` to `^0.3.0` (genesis_tree 0.3.0, InheritedModelSeed).
  No API changes in this package; the perception wire contract is unchanged.
  Retires the `genesis_perception: ^0.3.0` dependency override every hosted
  consumer on genesis_tree 0.3.0 had to carry (the_grid, power_station).

## 0.2.1

- Bump `genesis_perception` to `^0.2.0` (the genesis builder wave). No API
  changes in this package; the perception wire contract is unchanged.

## 0.2.0

- Breaking: VM-service methods now use `ext.leonard.*`. Construct names with
  `kLeonardExtensionPrefix` from `leonard_contract`.
- The handshake version is `kLeonardProtocolVersion` from `leonard_contract`.

## 0.1.0

- Initial release: the pure-Dart extension contract extracted from
  `leonard_flutter`. `LeonardExtension` / `LeonardTool`, the
  `PerceptionExtension` mixin, `ExtensionRegistry`, and the
  `dispatchToolToEnvelope` / `decodeServiceExtensionParams` VM-service dispatch
  helpers — Flutter-free, so a Flutter binding and a non-Flutter host share one
  contract.

  Pre-1.0 and experimental; APIs may change before 1.0.
