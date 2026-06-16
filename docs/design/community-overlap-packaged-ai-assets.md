# Community overlap: Dart-team "Packaged AI Assets" vs. lenny's consumer agent assets

**Date:** 2026-06-16 · **Status:** finding + what-we-shipped — direction confirmed with Nico (2026-06-16). This is **not** an autonomous register entry: the call was made together, so it does not belong in `docs/adrs/0000` (the AI-decision register). This doc + the spike bead carry it. Sibling of the Genkit (A3, `community-overlap-genkit.md`) and Dart-team-plumbing (A2) overlap analyses.

Triggered by Nico pointing at the Dart-team **"Packaged AI Assets"** proposal
([Google Doc](https://docs.google.com/document/d/1k_X-Sp4GQyZP6k9lvZ1Itj0GvzQZuWl3iKzi5AIa69Q/edit)),
and the recurring goal: a consumer who depends on `leonard_flutter` should get a
"drive/verify this Flutter app" capability in their own coding agent with **no
manual install**.

## The reframe (the thing that matters)

The agents/skills worth building are a **consumer deliverable**, not this repo's
internal `.agents/` tooling. A downstream app adds `leonard_flutter`; its coding
agent (Claude Code, Copilot CLI, …) should then be able to drive/verify the live
app. Distribution is the whole problem.

## What the proposal is

A package ships `extension/mcp/config.yaml` (the **same `extension/<name>/config.yaml`
discovery format lenny already uses for DevTools**). The Dart/Flutter MCP server
reads it from a consumer's **immediate dependencies** and surfaces:

- **resources** — docs/examples; fields: `name` (optional, defaults to file
  basename), `title` (required), `description` (required), `path` (required,
  package-relative), `visibility` (optional: `public` default | `private`).
  Exposed to the agent as `package-root://<package-name>/<path>`.
- **prompts** — `/slash` commands; same fields; if arguments are supplied the
  prompt file is rendered as a `package:mustache_template`. (Argument
  *declaration* syntax is underspecified in the proposal.)

Distribution = pub.dev itself; no separate registry.

## Two channels (we ship both)

| | harness-native (today) | pub-native (future) |
|---|---|---|
| Mechanism | `dart run leonard_cli:install` → `.agents/` | `extension/mcp/config.yaml` → Dart MCP |
| Status | **shipped** (0bfc9ac) | **forward-compat, inert** until the Dart MCP reads it |
| Home | `leonard_cli` (the executable consumer dev-deps) | `leonard_flutter` (the binding in the app's deps) |

**Shipped 2026-06-16:**
- `leonard_cli/lib/assets/skills/drive-flutter-app/SKILL.md` (agentskills,
  cross-client) + `assets/agents/leonard-{driver,pilot}.agent.md` (Copilot-CLI
  `.agent.md`); `bin/install.dart` copies them into the consumer's
  `.agents/{skills,agents}/`. Smoke-tested.
- `leonard_flutter/extension/mcp/config.yaml` + `resources/driving-with-leonard.md`
  + `prompts/drive-flutter-app.md` — faithful to the verbatim schema above,
  inert until the Dart MCP supports it.

## The moat (unchanged)

The proposal is *transport only* (pub.dev → Dart MCP → agent). The asset
**content** is lenny-specific — semantics-first perception, the
perceive→decide→act loop, the `leonard_drive` turn-by-turn surface, scroll
extent. No lock-in: identical content ships through both channels. MCP is in the
loop for the pub-native path, but the *distribution* is pub-native (no manual MCP
install), which is the part Nico cares about.

## Recommendation

**Track-and-align** (proposal not shipped; `extension/mcp` is experimental).
Keep `dart run leonard_cli:install` as the today-answer. Validate + finalize
`extension/mcp/config.yaml` — especially the prompt-argument declaration syntax —
once the Dart/Flutter MCP server reads it. Tracked: **spike bead** (validate the
config against a real Dart MCP build; wire the resource/prompt content to match
whatever final schema ships).
