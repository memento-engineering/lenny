---
status: accepted
date: 2026-09-08
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: image-goldens-use-caller-supplied-baselines
  surfaces:
    - "packages/leonard_cli/README.md"
    - "packages/leonard_cli/lib/src/cli_args.dart"
    - "packages/leonard_cli/lib/src/image_golden_comparator.dart"
    - "packages/leonard_cli/lib/src/run.dart"
    - "packages/leonard_cli/test/image_goldens/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Image goldens use caller-supplied baselines

## Context and Problem Statement

The repository already uses `packages/leonard_flutter/test/goldens/` for JSON
observation-shape fixtures. Pixel baselines need a distinct location and an
explicit runtime source so image comparison cannot be confused with perception
equivalence or silently enabled for every live run.

## Decision Outcome

Real runs compare only when the caller supplies `--goldens-dir`; omission means
capture-only. Each captured frame is paired with the same basename in that
directory, using only the current run's explicit frame list rather than scanning
either directory. `--update-goldens` requires `--goldens-dir`, creates or
overwrites each same-named baseline, prints every written path, and never
compares in the same invocation. Comparator fixtures live only under
`packages/leonard_cli/test/image_goldens/`.

### Consequences

* Good, because baseline ownership is explicit and stale files cannot enter a
  run's report.
* Bad, because callers must supply and maintain a baseline directory whenever
  they want comparison.
