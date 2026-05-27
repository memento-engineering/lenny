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

### Perf tests (`exploration_devtools`)

Tests tagged `perf` are excluded from `melos run test` by default (via `dart_test.yaml` in that package). To run them explicitly:

```bash
flutter test packages/exploration_devtools --tags=perf
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_
