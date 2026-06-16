# `.agents/` — canonical, cross-client agent + skill definitions

This is the **single source of truth** for lenny's own shared agents and skills,
in the harness-neutral [agentskills.io](https://agentskills.io) /
[Copilot CLI plugin](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins)
layout. It's all markdown (+ a little JSON) — no per-harness rewrite.

```
.agents/
  agents/   <name>.agent.md     # agents (Copilot CLI plugin + cross-client format)
  skills/   <name>/SKILL.md     # skills (the universal agentskills SKILL.md standard)
```

## Who reads it

- **Claude Code** reads `.claude/agents/` and `.claude/skills/`, which are
  machine-local (`.git/info/exclude` ignores `.claude/`). lenny's own entries
  there are **symlinks into this dir**, recreated on any checkout by
  `scripts/link-shared-agents.sh` (idempotent; also run automatically by
  `scripts/install-rig-committee.sh`). So there is one copy, edited here.
- **GitHub Copilot CLI** consumes the plugin layout at the repo root:
  `agents/ -> .agents/agents` and `skills/ -> .agents/skills` (symlinks), giving
  `agents/*.agent.md` + `skills/*/SKILL.md` as the spec expects.
- Any other agentskills-compliant client scans `.agents/skills/` directly.

## What lives here vs `.claude/`

- **Here (tracked, shared):** lenny's own, harness-neutral definitions
  (`lenny-pilot`, `lenny-driver`; skills `debug-inference`, `predictable-flutter`,
  `beads`). These are generic — no Claude-specific tools.
- **`.claude/` (Claude-private):** the Gas City factory committee agents
  (`architect`, `bitsmith`, `critique`) and factory skills, composed by
  `scripts/install-rig-committee.sh` from `.gascity-pack/`. Reproducible →
  gitignored.

## Editing

Edit files **here**. The `.claude/` symlinks pick up changes automatically; no
recompose needed for lenny's own content (the composer only manages factory
files). Add a new shared agent as `agents/<name>.agent.md` and symlink it into
`.claude/agents/<name>.md`; add a new shared skill as `skills/<name>/SKILL.md`.
