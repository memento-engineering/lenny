# Changelog

## 0.1.1

- `handshakeJson()` now reports a `capabilities` list for parity with the
  Flutter binding's handshake contract. A pure-Dart target has no screenshot,
  so the list is always empty — but it is present rather than absent, so a
  driver sees a uniform shape across hosts.

## 0.1.0

- Initial release: `ExplorationHost` hosts a set of `leonard_contract`
  extensions over the `ext.exploration.*` VM-service surface (handshake,
  `get_stable_observation`, per-tool dispatch) via `dart:developer`, so a
  non-Flutter Dart program can be driven live by `leonard_cli` / `leonard_drive`.

  Pre-1.0 and experimental; APIs may change before 1.0.
