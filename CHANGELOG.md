# Changelog

All notable changes to Leonard (dev codename: lenny) are recorded here.

## 0.1.0

First tagged release — a Flutter agent harness that exposes a running app's
state to an autonomous agent over the VM service.

### Perception
- Single-path observation pipeline. Observations are produced by a declarative
  `build() -> Perception` tree (built on `genesis_perception`, the measurement
  domain over the `tree` spine). The legacy `observe() -> fragment` dual path is
  retired — there is one perception path.
- `core`, `dio`, `riverpod`, and `router` are all perception-native.

### Authoring
- Extension contract: a `LeonardExtension` implements `build()` to contribute a
  namespaced fragment; `ExtensionContext`, `ExtensionRegistry`, and the DevTools
  ("Leonard") panel round it out.

### Rebrand
- Packages renamed `exploration_* -> leonard_*`; terminology `plugin -> extension`
  throughout, including the serialized wire (`extensions` key).
- VM-service prefix remains `ext.exploration.*` (protocol-stable).

### Dependencies
- Perception is consumed from the published `genesis_perception ^0.1.1` (pub.dev),
  making the workspace self-contained for any cloner/CI runner.
