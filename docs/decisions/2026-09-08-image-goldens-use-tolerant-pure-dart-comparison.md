---
status: accepted
date: 2026-09-08
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: image-goldens-use-tolerant-pure-dart-comparison
  surfaces:
    - "packages/leonard_cli/pubspec.yaml"
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

# Image goldens use tolerant pure-Dart comparison

## Context and Problem Statement

`leonard_cli` is a pure-Dart package, so Flutter engine APIs such as
`matchesGoldenFile` and `dart:ui` image codecs are unavailable. The CLI needs
to judge PNG screenshots already serialized into trajectories without adding a
Flutter test harness or changing the VM-service perception contract governed
by `a2-community-overlap-finding-adopt-dart-team-plumbing-keep-t` and
`adr-0002-perception-migration`.

## Considered Options

`matchesGoldenFile` and `dart:ui.instantiateImageCodec` were rejected because
they require Flutter. Reusing an incumbent pure-Dart decoder was not possible
because no workspace package decoded images. `package:image` supplies the
maintained pure-Dart PNG decoder required at the CLI boundary.

## Decision Outcome

Add `package:image` only to `leonard_cli` and decode both PNGs there. Different
dimensions fail without scaling, cropping, or resampling. For equal dimensions,
a pixel differs when any decoded RGBA channel delta is strictly greater than a
configurable integer tolerance from 0 through 255, defaulting to 8. The frame
fails only when the differing-pixel ratio is greater than a configurable finite
ratio from 0.0 through 1.0, defaulting to 0.0.

### Consequences

* Good, because image comparison remains usable from `dart test` and the live
  pure-Dart CLI.
* Bad, because `leonard_cli` gains a PNG-decoding dependency and intentionally
  provides no perceptual or resampling comparison mode.
