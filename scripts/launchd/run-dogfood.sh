#!/usr/bin/env bash
# Nightly dogfood runner for the lenny swift-infer e2e suite.
# Driven by com.nicospencer.lenny.dogfood.plist (StartInterval=21600).
# Secrets sourced from ~/.lenny-dogfood.env — never stored in the plist.
set -euo pipefail

# ── resolve repo root relative to this script ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── change to repo root for dart test and bd ───────────────────────────────
cd "$REPO_ROOT"

# ── source secrets (not inherited from login shell in launchd context) ─────
ENV_FILE="$HOME/.lenny-dogfood.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[dogfood] ERROR: $ENV_FILE not found. Create it with SWIFT_INFER_ENDPOINT and SWIFT_INFER_AGENT_TOKEN." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"
export SWIFT_INFER_ENDPOINT SWIFT_INFER_AGENT_TOKEN

# ── log dir ────────────────────────────────────────────────────────────────
LOG_DIR="$HOME/Library/Logs/lenny-dogfood"
mkdir -p "$LOG_DIR"
LAST_STATUS_FILE="$LOG_DIR/last_status"
TS="$(date +%s)"

echo "[dogfood] run start ts=$TS endpoint=${SWIFT_INFER_ENDPOINT:-<unset>}"

# ── run the three canonical e2e scenarios ─────────────────────────────────
# dart test exits non-zero if any test fails.
DART_EXIT=0
dart test \
  --timeout=5m \
  "$REPO_ROOT/packages/exploration_agent/test/e2e/dogfood_e2e_test.dart" \
  2>&1 || DART_EXIT=$?

# ── determine current run outcome ─────────────────────────────────────────
if [[ "$DART_EXIT" -eq 0 ]]; then
  CURRENT="healthy"
else
  CURRENT="failing"
fi

# ── read prior status for flake suppression ───────────────────────────────
PRIOR="healthy"
if [[ -f "$LAST_STATUS_FILE" ]]; then
  PRIOR="$(cat "$LAST_STATUS_FILE")"
fi

# ── write updated last_status ─────────────────────────────────────────────
echo "$CURRENT" > "$LAST_STATUS_FILE"

# ── state machine ─────────────────────────────────────────────────────────
# Green recovery: immediate, no hysteresis.
if [[ "$CURRENT" == "healthy" ]]; then
  bd set-state lenny-g8y health=healthy \
    --reason "All 3 e2e scenarios passed (ts=$TS)"
  echo "[dogfood] run complete: healthy"
  exit 0
fi

# current=failing branch
# Two-of-two-consecutive rule: only escalate when prior was also failing.
if [[ "$PRIOR" == "failing" ]]; then
  # Confirmed regression (2 consecutive failures).
  # Check if already failing to avoid re-firing the notification.
  ALREADY_FAILING=0
  if bd show lenny-g8y 2>/dev/null | grep -q "health:failing"; then
    ALREADY_FAILING=1
  fi

  bd set-state lenny-g8y health=failing \
    --reason "2 consecutive failures — dart exit=$DART_EXIT (ts=$TS)"

  if [[ "$ALREADY_FAILING" -eq 0 ]]; then
    # Transition healthy→failing: fire macOS banner.
    MSG="Lenny dogfood: 2 consecutive failures — check bd show lenny-g8y"
    osascript -e "display notification \"$MSG\" with title \"Lenny dogfood\""
  fi
  echo "[dogfood] run complete: failing (confirmed, 2-of-2)"
else
  # current=failing but prior=healthy → single-shot red, suppress escalation.
  echo "[dogfood] run complete: failing (suppressed, 1-of-2 flake guard)"
fi

# Always exit 0 so launchd does not throttle on repeated failures.
exit 0
