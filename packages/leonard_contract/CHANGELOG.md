# Changelog

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
