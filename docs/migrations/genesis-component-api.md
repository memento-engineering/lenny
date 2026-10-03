# Genesis component API migration

Leonard now exposes the canonical Genesis component vocabulary introduced by
`genesis_perception 0.4.0-dev.1`. This is a source-vocabulary migration. It does
not change Leonard's extension namespaces, observation shapes, reconciliation
identity, inherited dependency behavior, or build purity.

## Symbol and member map

| Deprecated source spelling | Canonical spelling |
| --- | --- |
| `Seed` | `Component` |
| `Branch` | `Element` |
| `TreeContext` | Genesis `BuildContext` |
| `TreeOwner` | `BuildOwner` |
| `seed` | `component` |
| `branchId` | `elementId` |
| inherited-seed lookup names | inherited-value lookup names |
| `buildCorePerceptionSeed` | `buildCorePerceptionComponent` |
| `TreeNode.seedType` | `TreeNode.componentType` |

`Perception`, `PerceptionContext`, `Node`, and `Field` remain meaningful domain
names and are unchanged.

## Dependency floors

| Package | Release | Required floor |
| --- | --- | --- |
| `leonard_contract` | `0.2.6` | `genesis_perception: ^0.4.0-dev.1` |
| `leonard_host` | `0.2.4` | `leonard_contract: ^0.2.6` |
| `leonard_flutter` | `0.4.1` | `leonard_contract: ^0.2.6` |
| `leonard_dio` | `0.4.1` | `leonard_flutter: ^0.4.1` |
| `leonard_riverpod` | `0.4.1` | `leonard_flutter: ^0.4.1` |
| `leonard_router` | `0.4.1` | `leonard_flutter: ^0.4.1` |
| `leonard_tmux` | `0.2.3` | `leonard_host: ^0.2.4` |
| `leonard_native` | `0.4.2` | `leonard_host: ^0.2.4` |
| `leonard_devtools` | `0.4.0-dev.2` | `genesis_foundation: ^0.3.0-dev.1` |

The eight perception-producing Leonard packages directly require
`genesis_perception: ^0.4.0-dev.1`. These are hosted constraints; do not commit
local path overrides.

## Extension compatibility

Genesis retains deprecated identity-preserving aliases whose semantics match
the canonical types. Existing third-party extensions may continue to override
`buildPerception()` with `Seed` while upgrading Leonard. New implementations
should return `Component`. Deprecated forwarding members cover renamed tree
members during this compatibility window; their removal is a separate
follow-up after consumers migrate.

Both spellings remain synchronous. `buildPerception()` and every Genesis
`build()` must be a pure read: no writes, I/O, awaiting, or effect execution.
Keep watchers and polling in `initialize()`, and use
`prepareForObservation()` only to publish already-buffered state.

## Flutter collisions

Flutter owns its own `Widget`, `Element`, and `BuildContext`. Keep those names
for Flutter objects and prefix Genesis in files that import both libraries:

```dart
import 'package:flutter/widgets.dart';
import 'package:genesis_perception/genesis_perception.dart' as genesis;

Element? flutterRoot;
genesis.Element? perceptionRoot;

genesis.Component buildPerception(genesis.PerceptionContext context) =>
    const genesis.Node('example');
```

## Diagnostics wire compatibility

Source code constructs and reads `TreeNode.componentType`. Diagnostics contract
version 1 deliberately continues to encode and decode the literal `seedType`
JSON key. A `componentType` JSON key is not emitted. Changing that wire key
would require a separately versioned protocol migration.

## Scope boundary

This migration covers Leonard's perception contract, hosts, extensions, and
workspace compile consumers. The downstream
`grid_assets/leonard_grid_assets` package is excluded: it follows the migrated
grid and power packages separately, avoiding a grid → Leonard grid-assets →
grid dependency cycle.
