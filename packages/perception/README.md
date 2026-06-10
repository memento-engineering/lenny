# perception

Pure-Dart declarative perception framework core.

Perception becomes a pure function of app state:

```
AppState ── build ──▶ Perception tree ── harvest ──▶ Observation
  (Flutter:  State  ── build ──▶ Widget tree ── layout/paint ──▶ pixels)
```

This package is the `perception` layer from [ADR 0001](../../docs/adrs/0001-declarative-perception-framework.md).
It has zero Flutter dependencies and runs in any Dart isolate.

## Status

Scaffolded (Phase 1a, ADR 0002). Full implementation in follow-on tasks.

## Package topology

```
        perception   ← this package (pure Dart core)
        ▲      ▲      ▲
perception_flutter   exploration_dio   exploration_riverpod  ...
```
