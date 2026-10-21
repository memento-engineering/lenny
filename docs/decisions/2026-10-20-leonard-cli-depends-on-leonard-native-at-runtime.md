---
status: accepted
date: 2026-10-20
decision-makers:
  - "Nico Spencer"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: leonard-cli-depends-on-leonard-native-at-runtime
  surfaces:
    - "packages/leonard_cli/pubspec.yaml"
    - "packages/leonard_cli/lib/src/native_host_resolution.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-rzu3w
  legacy-id: null
---

# leonard_cli depends on leonard_native at runtime

## Context and Problem Statement

`leonard_drive up` finds the `leonard_native` host script through the running
program's package config (`Isolate.resolvePackageUri`), the lenny#160 fix in
`leonard_cli` 0.4.0. But `leonard_cli` listed `leonard_native` under
`dev_dependencies`, so a consumer that depends only on `leonard_cli` has no
`leonard_native` in its package config. The lookup returned `null` and fell
back to working-directory candidates that exist only inside a lenny checkout:
lenny#160 again, filed as lenny#199.

## Decision Outcome

* **`leonard_native` is a runtime dependency of `leonard_cli`** (`^0.6.0`,
  under `dependencies`). It is pure Dart, so the CLI stays Flutter-free.
  `leonard_contract` and `leonard_host` stay dev dependencies: no `lib/` or
  `bin/` code imports them. Ruled by Nico, 2026-10-20.
* **A host miss fails loudly with its cause.** When no `--native-host` is
  passed, the package config does not resolve `leonard_native`, and no
  checkout-relative candidate exists, `up` exits 64 saying `leonard_native`
  is missing from the package config and how to fix it. The working-directory
  fallback stays for development inside a lenny checkout.

### Consequences

* Good, because depending on `leonard_cli` alone is enough for `up`'s native
  path from any directory, and an AOT build or a stripped package config gets
  an error naming the real cause.
* Bad, because every `leonard_cli` consumer now resolves `leonard_native` and
  its dependencies (`genesis_perception`, `http`, `leonard_contract`,
  `leonard_host`, `xml`), even one that never uses
  the native channel.
