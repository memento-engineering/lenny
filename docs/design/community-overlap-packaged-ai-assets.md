# Community overlap: Dart-team "Packaged AI Assets" vs. lenny's consumer agent assets

**Date:** 2026-06-16 · **Status:** finding + what-we-shipped — direction confirmed with Nico (2026-06-16). This is **not** an autonomous register entry: the call was made together, so it does not belong in `docs/adrs/0000` (the AI-decision register). This doc + the spike bead carry it. Sibling of the Genkit (A3, `community-overlap-genkit.md`) and Dart-team-plumbing (A2) overlap analyses.

Triggered by Nico pointing at the Dart-team **"Packaged AI Assets"** proposal
([Google Doc](https://docs.google.com/document/d/1k_X-Sp4GQyZP6k9lvZ1Itj0GvzQZuWl3iKzi5AIa69Q/edit)),
and the recurring goal: a consumer of Leonard should get a "drive/verify my
running program" capability in their own coding agent with **no manual install**.

## The reframe (the thing that matters)

The agents/skills worth building are a **consumer deliverable**, not this repo's
internal `.agents/` tooling. A downstream project adds Leonard (the
`leonard_flutter` binding for a Flutter app, or another target's extension); its
coding agent (Claude Code, Copilot CLI, …) should then be able to drive/verify
the running target. Distribution is the whole problem.

**Leonard is a Dart-VM tool, not Flutter-specific** — `leonard_agent` is the
pure-Dart core, and `leonard_tmux` drives an external process with zero Flutter.
So the consumer assets must NOT be scoped to Flutter, and must NOT be gated
behind the `leonard_flutter` binding. (Earlier drafts put them there; corrected.)

## What the proposal is

A package ships `extension/mcp/config.yaml` (the **same `extension/<name>/config.yaml`
discovery format lenny already uses for DevTools**). The Dart/Flutter MCP server
reads it from a consumer's **immediate dependencies** and surfaces:

- **resources** — docs/examples; fields: `name` (optional, defaults to file
  basename), `title` (required), `description` (required), `path` (required,
  package-relative), `visibility` (optional: `public` default | `private`).
  Exposed as `package-root://<package-name>/<path>`.
- **prompts** — `/slash` commands; same fields; if arguments are supplied the
  prompt file is rendered as a `package:mustache_template`. (Argument
  *declaration* syntax is underspecified in the proposal.)

Distribution = pub.dev itself; no separate registry.

## Two channels (we ship both), both homed in `leonard_cli`

`leonard_cli` is the right home for BOTH channels: it's the **pure-Dart driver
every Leonard target uses** (Flutter or not), the package a consumer dev-depends
on to drive. Homing the assets there keeps Leonard target-agnostic; homing them
in `leonard_flutter` would wrongly imply "you need a Flutter app."

| | harness-native (today) | pub-native (future) |
|---|---|---|
| Mechanism | `dart run leonard_cli:install` → `.agents/` (+ `--claude`/`--copilot`) | `extension/mcp/config.yaml` → Dart MCP |
| Status | **shipped** | **forward-compat, inert** until the Dart MCP reads it |
| Home | `leonard_cli` | `leonard_cli` |

**Shipped 2026-06-16:**
- `leonard_cli/lib/assets/skills/drive-with-leonard/SKILL.md` (agentskills,
  cross-client, **target-agnostic**) + `assets/agents/leonard-{driver,pilot}.agent.md`
  (Copilot-CLI `.agent.md`); `bin/install.dart` copies them into the consumer's
  `.agents/{skills,agents}/`, with `--claude` / `--copilot` / `--all` symlink
  overlays into each harness's native dir (one source of truth).
- `leonard_cli/extension/mcp/config.yaml` — resource points at the installed
  skill (`lib/assets/skills/drive-with-leonard/SKILL.md`, no drift) + a
  `/drive-app` prompt. Faithful to the verbatim schema; inert until the Dart MCP
  reads it.

## The moat (unchanged)

The proposal is *transport only* (pub.dev → Dart MCP → agent). The asset
**content** is lenny-specific — semantics-first perception, the
perceive→decide→act loop, the `leonard_drive` turn-by-turn surface. No lock-in:
identical content ships through both channels. MCP is in the loop for the
pub-native path, but the *distribution* is pub-native (no manual MCP install).

## Known gap surfaced by this work

**Live VM-service driving is Flutter-only today.** `developer.registerExtension`
for `ext.exploration.*` (the host the CLI connects to) lives only in
`leonard_flutter` (`LeonardBinding`). `leonard_tmux` proves the
extension/perception model is target-agnostic, but its example uses the
extension **as a library** (`observe()`/`executeAction()`), not over the VM
service via `leonard_cli`. A **pure-Dart VM-service host** (so a non-Flutter
program can be driven live by the CLI) is the missing piece — tracked as a bead.
The `drive-with-leonard` skill is honest about this.

## Recommendation

**Track-and-align** (proposal not shipped; `extension/mcp` is experimental).
Keep `dart run leonard_cli:install` as the today-answer. Validate + finalize
`extension/mcp/config.yaml` (esp. the prompt-argument declaration syntax) once
the Dart/Flutter MCP server reads it. Two beads: (1) validate the MCP config
against a real Dart MCP build; (2) build the pure-Dart VM-service host for
non-Flutter targets.
