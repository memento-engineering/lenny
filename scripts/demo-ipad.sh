#!/usr/bin/env bash
# Turnkey helper for the text-based iPad exploration-agent demo.
#
#   scripts/demo-ipad.sh up     # relaunch sample_app on the iPad, wait for VM URI
#   scripts/demo-ipad.sh tail   # pretty live-tail (auto-latch) — run INSIDE `asciinema rec`
#   scripts/demo-ipad.sh run    # run the compound-goal exploration (qwen-mlx) against it
#
# Typical recording flow:
#   1) scripts/demo-ipad.sh up                         # launch the app fresh, prints ws=
#   2) pane A:  asciinema rec /tmp/lenny-demo.cast      # then: scripts/demo-ipad.sh tail
#   3) pane B:  scripts/demo-ipad.sh run               # the tail latches onto it
#   4) when done: Ctrl-C the tail, Ctrl-D to stop asciinema
#   5) optional: agg /tmp/lenny-demo.cast /tmp/lenny-demo.gif
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/packages/exploration_flutter/example/sample_app"
CLI="$ROOT/packages/exploration_cli"
UDID=00008110-001651523CE3801E
LOG=/tmp/lenny_ipad.log
WSFILE=/tmp/lenny_ipad_ws.txt
GOAL='Sign in with email demo@example.com and password password. Then open Settings and turn on Dark Theme. Then go back to Home, open the Terms screen, scroll down to the bottom, and turn on Accept Terms.'

case "${1:-}" in
  up)
    pkill -f "run -d $UDID" 2>/dev/null || true
    pkill -f "iproxy.*$UDID" 2>/dev/null || true
    sleep 3
    : > "$LOG"
    ( cd "$APP" && nohup flutter run -d "$UDID" --no-devtools > "$LOG" 2>&1 & )
    echo "launching sample_app on iPad (fresh: starts at /login)…"
    url=""
    for _ in $(seq 1 90); do
      url=$(grep -o 'http://127.0.0.1:[0-9]*/[^ ]*/' "$LOG" 2>/dev/null | tail -1)
      [ -n "$url" ] && break
      sleep 2
    done
    [ -z "$url" ] && { echo "ERROR: no VM URI after ~3min; tail $LOG"; exit 1; }
    ws="ws://${url#http://}ws"
    echo "$ws" > "$WSFILE"
    echo "READY  ws=$ws"
    ;;
  tail)
    exec python3 "$ROOT/scripts/swift-infer-pretty-tail.py"
    ;;
  run)
    [ -f "$WSFILE" ] || { echo "run 'scripts/demo-ipad.sh up' first"; exit 1; }
    ws=$(cat "$WSFILE")
    cd "$CLI"
    # shellcheck disable=SC1090
    source ~/.lenny-dogfood.env
    exec dart run bin/exploration_cli.dart \
      --vm-uri "$ws" --goal "$GOAL" \
      --plugins router,riverpod,dio --model qwen-mlx --policy action-relative \
      --output trajectories/demo-ipad-compound-qwen.jsonl
    ;;
  goal) echo "$GOAL" ;;
  *) echo "usage: scripts/demo-ipad.sh {up|tail|run|goal}"; exit 2 ;;
esac
