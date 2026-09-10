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

dart run tool/e2e.dart e2e \
  --sample-suite \
  --sample-scenario login \
  --model qwen-mlx \
  --device DEVICE_ID
```

`--sample-scenario` is valid only with `--sample-suite`; its accepted values are
`login`, `navigation`, `state_change`, and `scroll`. Omitting it preserves the
four-scenario order. The service API follows the same composition:
`E2eService.runSampleSuite` defaults `scenarios` to `kLeonardSampleSuite`, while
direct `performE2eSampleSuite` callers must provide a non-empty scenario list.

Both modes emit exactly one JSON object. A child's prose and exit status never
decide the result; `SessionHeader`, `TurnRecord`, and `SessionFooter` evidence
does. The four circuit capability ids are `e2e-preflight`, `e2e-launch`,
`e2e-run`, and `e2e-inspect`. `buildLeonardRegistry` composes them and the
existing selfdrive capabilities over the ordinary code registry.

Every driver run stores Leonard CLI's raw attachment probe as `probe.json`
beside `trajectory.jsonl`. The probe is diagnostic evidence only; the typed
trajectory inspector remains the sole verdict source.

The required corrected device pair is `leonard_agent` 0.3.1 with
`leonard_cli` 0.3.0. Device probing verified that application registration and
VM attachment were healthy under 0.3.0: the attached isolate returned populated
core tool descriptors, routes, and semantics. The qwen-mlx provider instead
represented schema-declared numeric arguments such as `node_id` and `seconds`
as JSON strings. Strict pre-dispatch validation exhausted its retries, after
which the terminal synthetic failure record carried an empty observation. Agent
0.3.1 fixes that boundary by losslessly normalizing schema-declared numeric
strings before applying the unchanged strict validation.

This package does not compose itself into a station and its manifest contains
no station `grid:` block.

Part of the [lenny](https://github.com/memento-engineering/lenny) workspace.
