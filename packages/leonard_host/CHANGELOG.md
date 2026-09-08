# Changelog

## 0.2.2

- Fix: widen `genesis_perception` to `>=0.2.0 <0.4.0`. Published 0.2.1 pinned
  `^0.2.0`, which cannot resolve alongside `leonard_contract` 0.2.2 (which
  requires `genesis_perception ^0.3.0`) — version solving failed outright for any
  consumer taking both. No API changes.
- Raise the `leonard_contract` floor to `^0.2.2`. The declared `^0.2.0` floor was
  unsatisfiable — `leonard_contract` 0.2.0 requires `genesis_perception ^0.1.3`,
  which this package's own `>=0.2.0 <0.4.0` range forbids — so a resolver
  silently held `leonard_contract` back to 0.2.1 instead of taking 0.2.2.

## 0.2.1

- Bump `genesis_perception` to `^0.2.0` (the genesis builder wave). No API
  changes in this package; the perception wire contract is unchanged.

## 0.2.0

- Breaking: VM-service methods now use `ext.leonard.*`. Construct names with
  `kLeonardExtensionPrefix` from `leonard_contract`.
- The default handshake version is `kLeonardProtocolVersion` from
  `leonard_contract`.

## 0.1.1

- `handshakeJson()` now reports a `capabilities` list for parity with the
  Flutter binding's handshake contract. A pure-Dart target has no screenshot,
  so the list is always empty — but it is present rather than absent, so a
  driver sees a uniform shape across hosts.

## 0.1.0

- Initial release: `ExplorationHost` hosts a set of `leonard_contract`
  extensions over the `ext.leonard.*` VM-service surface (handshake,
  `get_stable_observation`, per-tool dispatch) via `dart:developer`, so a
  non-Flutter Dart program can be driven live by `leonard_cli` / `leonard_drive`.

  Pre-1.0 and experimental; APIs may change before 1.0.
