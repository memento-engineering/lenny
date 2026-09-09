# leonard_grid_assets

Lenny's grid assets for a the_grid station: the station-driven `selfdrive` and
`leonard-e2e` circuits, their shared capability registry, and the deterministic
`E2eCommand`. The E2E service preflights a wired iOS device, launches a fresh
Flutter app, invokes `leonard_cli`, and derives one structured verdict from the
typed trajectory. Each invocation explicitly pins Leonard's packaged operating
guide so dependency-launched CLI snapshots cannot silently fall back to a
goal-only prompt. The private sample-suite mode composes four calls to that same
operation against `packages/leonard_flutter/example/sample_app`.

The development runner registers only the Command:

```console
dart run tool/e2e.dart e2e \
  --goal 'Open Settings' \
  --app-dir /absolute/path/to/flutter_app \
  --expect-route settings

dart run tool/e2e.dart e2e --sample-suite --device DEVICE_ID
```

Both modes emit exactly one JSON object. A child's prose and exit status never
decide the result; `SessionHeader`, `TurnRecord`, and `SessionFooter` evidence
does. The four circuit capability ids are `e2e-preflight`, `e2e-launch`,
`e2e-run`, and `e2e-inspect`. `buildLeonardRegistry` composes them and the
existing selfdrive capabilities over the ordinary code registry.

This package does not compose itself into a station and its manifest contains
no station `grid:` block.

Part of the [lenny](https://github.com/memento-engineering/lenny) workspace.
