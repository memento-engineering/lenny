#!/usr/bin/env bash
# Link lenny's shared, cross-client agents + skills (canonical source in
# .agents/, the agentskills.io / Copilot-CLI-plugin layout) into the local
# Claude Code harness dir (.claude/), which is machine-local (.git/info/exclude
# ignores .claude/). Idempotent — safe to re-run.
#
# Why a script: .agents/ is tracked and travels on clone (so Copilot CLI, whose
# plugin layout is the root `agents/`+`skills/` symlinks -> .agents/, and any
# agentskills-compliant client scanning .agents/skills/, work with zero setup).
# Claude Code reads .claude/; since that dir is local, we recreate the bridge
# symlinks here rather than tracking them. Factory agents/skills are composed
# separately by scripts/install-rig-committee.sh and are NOT touched here.
set -euo pipefail
cd "$(dirname "$0")/.."

link() { # <target-relative-to-link-dir> <link-path>
  local target="$1" link="$2"
  mkdir -p "$(dirname "$link")"
  # Replace any stale file/dir/symlink so re-runs converge (-L catches a
  # broken symlink, which -e reports as absent).
  if [ -e "$link" ] || [ -L "$link" ]; then rm -rf "$link"; fi
  ln -s "$target" "$link"
  printf '  %s -> %s\n' "$link" "$target"
}

echo "Linking lenny's shared agents into .claude/ ..."
for a in .agents/agents/lenny-*.agent.md; do
  [ -e "$a" ] || continue
  base="$(basename "$a" .agent.md)"
  link "../../$a" ".claude/agents/$base.md"
done

echo "Linking lenny's shared skills into .claude/ ..."
for d in .agents/skills/*/; do
  name="$(basename "$d")"
  case "$name" in
    # factory skills are composed by install-rig-committee.sh; skip.
    critique|deliberate|discover|factory|factoryskills|forge|land|marshal|merge|route|specify) continue ;;
  esac
  [ -f "$d/SKILL.md" ] || continue
  link "../../.agents/skills/$name" ".claude/skills/$name"
done

echo "Done. (Copilot CLI: root agents/ + skills/ symlinks already point at .agents/.)"
