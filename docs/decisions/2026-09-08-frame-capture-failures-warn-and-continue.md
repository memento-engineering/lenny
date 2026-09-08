---
status: accepted
date: 2026-09-08
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: frame-capture-failures-warn-and-continue
  surfaces:
    - "packages/leonard_cli/lib/src/frame_capture_sink.dart"
    - "packages/leonard_cli/lib/src/run.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Frame capture failures warn and continue

## Context and Problem Statement

Frame persistence decorates the trajectory sink for every live run. Invalid
Base64, permissions, or disk failures must not turn a run that durably wrote its
trajectory into a harness failure, while failures in the underlying trajectory
write must still propagate.

## Considered Options

Writing a `frames.log` beside the frames directory was rejected because that
directory may be the failing resource and it adds another retained artifact.
Reporting one warning to the CLI's existing standard-error sink keeps the
failure visible without creating a second logging path.

## Decision Outcome

Forward and await each trajectory line before attempting frame persistence. A
capture failure records no frame path, does not retry, and returns normally.
Emit exactly one physical standard-error line per skipped qualifying turn as
`warning: frame capture skipped turn <index>: <cause>`, replacing every run of
carriage returns or line feeds in the cause with one space. Delegate write
failures continue to propagate, and only an explicit image-golden comparison
failure may change an otherwise clean run's exit code.

### Consequences

* Good, because optional frame evidence cannot weaken the trajectory's existing
  durability and exit-code contract.
* Bad, because capture-only automation must inspect warnings to detect missing
  frames.
