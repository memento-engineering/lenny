#!/usr/bin/env bash
# Install lenny's OWN rig committee skills — the second-rig dogfood (ADR 0011/0012/0013).
#
# lenny runs the GENERIC, stack-neutral factoryskills pack on itself, then injects
# its Dart/Flutter opinions (melos run analyze/test/format) through its rig overlay
# (.gascity-pack). This composes the two into the rig's committee skills so the
# committee — which resolves the rig's OWN skills, rig-local-first (ADR 0013) —
# grades lenny's Dart code with the Dart rubrics, NOT factoryskills' Go rubrics.
# Confirm with `fs config committee`.
#
# Idempotent. Run it once per checkout, and again after editing .gascity-pack/ (it
# composes COPIES, not devmode symlinks, so overlay edits are not live in the
# committee until re-composed). Local-only: .agents/skills and .claude/skills are
# gitignored.
#
# Requires a current `fs` on PATH (one with `fs init --overlay` + rig-local
# committee resolution — factoryskills >= the ADR 0013 build). `go install ./cmd/fs`
# from a factoryskills checkout, or `brew upgrade factoryskills`.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY=".gascity-pack/overlay/.claude/skills"
[ -d "$OVERLAY" ] || { echo "missing $OVERLAY — run from the lenny checkout" >&2; exit 1; }

# lenny is already bd-initialized (the city adopts its existing .beads/); fs init's
# bd-config steps are idempotent no-ops here. The load-bearing effect is the
# skills install + Dart overlay, which run BEFORE fs init's formula step — and that
# step can fail in a dolt-migrated repo whose .beads/formulas/*.json fixtures were
# dropped (factoryskills-69l). That failure is benign for the committee; verify the
# real outcome with `fs config committee` below.
if ! fs init --claude --overlay "$OVERLAY"; then
	echo "note: fs init returned non-zero (likely the formula-install step in a" >&2
	echo "      dolt-migrated repo, factoryskills-69l). Skills + overlay run first;" >&2
	echo "      verifying the committee below." >&2
fi

echo
echo "Committee now grades with (rig-local, ADR 0013):"
fs config committee
