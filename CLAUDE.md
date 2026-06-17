# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

Install Melos (once, globally):

```bash
dart pub global activate melos
```

Then, from the repo root:

```bash
melos run test       # Run all tests (pure-Dart + Flutter; excludes perf + dogfood e2e)
melos run analyze    # Run dart analyze on the workspace
melos run format     # Check formatting (fails if files need changes)
melos run test:e2e   # Run the live dogfood e2e test (see env requirements below)
melos run            # List all available scripts with descriptions
```

### Dogfood e2e (`melos run test:e2e`)

Requires two environment variables:

- `SWIFT_INFER_ENDPOINT` — base URL of the swift-infer service
- `SWIFT_INFER_AGENT_TOKEN` — bearer token

The test self-skips when these are absent, so `melos run test:e2e` is safe to run locally without them — all three scenarios will be reported as skipped.

### Perf tests (`leonard_devtools`)

Tests tagged `perf` are excluded from `melos run test` by default (via `dart_test.yaml` in that package). To run them explicitly:

```bash
flutter test packages/leonard_devtools --tags=perf
```

## Architecture Overview

Leonard lets an LLM perceive and drive a *running* Dart program over the VM
service. Layering (low → high):

- **`leonard_contract`** — pure-Dart extension contract: `LeonardExtension` /
  `LeonardTool`, the `PerceptionExtension` mixin (`buildPerception() → Seed`),
  `ExtensionRegistry`, and the tool-dispatch/param-decode helpers. No Flutter.
- **Hosts** serve the `ext.exploration.*` VM-service surface (handshake,
  `get_stable_observation`, per-tool dispatch) from a set of extensions:
  - `leonard_flutter` (`LeonardBinding`) — the Flutter host (semantics, routes,
    screenshot, plus extensions).
  - `leonard_host` (`ExplorationHost`) — the pure-Dart host for any non-Flutter
    Dart program (extensions only; no Flutter core fragment).
- **`leonard_agent`** — the brain/harness and driver client (`LeonardSession`,
  `VmServiceClient`, the loop); `leonard_cli` / `leonard_drive` are its CLIs. It
  is target-agnostic — it speaks the same `ext.exploration.*` surface whether
  the target is Flutter or pure Dart.
- **Extensions** contribute tools + an observation fragment under their
  namespace: `core` (Flutter actions), `router`/`riverpod`/`dio` (Flutter),
  `leonard_tmux` (pure-Dart, drives an external tmux process).

## Conventions & Patterns

### Perception is pull-free: build synchronously, watch out-of-band

A perception never gathers or performs I/O at observation time.
`buildPerception()` is a **synchronous** read of already-current in-memory
state. Whatever is observed — Flutter widget state, a Riverpod container, an
external process — is tracked by an **out-of-band watcher** (a listener, stream
subscription, or poll loop) that keeps a live snapshot current. The watcher's
async startup belongs in `initialize()` (which is `async`); the observe/build
path stays synchronous.

**Never make `buildPerception()` async.** If you're tempted to, you actually
need a stateful watcher feeding a snapshot.

Why: it keeps observation cheap, deterministic, and *uniform across hosts* — the
same sync contract serves the Flutter binding and the pure-Dart `ExplorationHost`
regardless of whether the source is in-memory or async I/O. Gather-on-demand
leaks the source's latency into the observation hot path and forces every host
and consumer to be async.

Precedents:
- `RiverpodLeonardExtension` — a `ProviderObserver` watches the container;
  `buildPerception()` reads the live observer state (`prepareForObservation()`
  just drains pending changes).
- `TmuxExtension` (`leonard_tmux`) — `initialize()` subscribes to a
  `genesis_tmux` `PollObservationSource`; `TmuxEvent`s refresh a cached
  `TmuxObservation`; `buildPerception()` reads it sync.
