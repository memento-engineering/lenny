---
status: accepted
date: 2026-09-08
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: frame-directories-follow-trajectory-paths
  surfaces:
    - "packages/leonard_cli/README.md"
    - "packages/leonard_cli/lib/src/file_trajectory_sink.dart"
    - "packages/leonard_cli/lib/src/frame_capture_sink.dart"
    - "packages/leonard_cli/lib/src/run.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Frame directories follow trajectory paths

## Context and Problem Statement

Live driving already resolves one trajectory path per run. Both the bare CLI
and station self-drive lane need screenshot files to remain beside that run's
other evidence without introducing another required path or a second run-naming
scheme.

## Decision Outcome

Derive the default frames directory as
`join(dirname(trajectoryPath), basenameWithoutExtension(trajectoryPath) +
'.frames')`. Name frames `turn-<index>.png`, using the turn record's own index
zero-padded to four digits. `--frames-dir` may override only frame placement.
The CLI never scans, deletes, or prunes a frames directory; retention belongs to
the caller.

### Consequences

* Good, because default CLI runs and station runs both colocate frames with the
  trajectory through one deterministic rule.
* Bad, because callers that retain trajectories also retain every captured
  frame unless they clean them up explicitly.
