#!/usr/bin/env bash
set -euo pipefail

# On-demand e2e of gc_pack/leonard in a throwaway Gas City.
#
#   tool/gc_pack_e2e.sh [infra] [pass] [fail]     (default: all three)
#
# Builds a private city under $TMPDIR (pinned gc and bd release binaries, its
# own GC_HOME, Dolt servers and subprocess sessions, the foreground controller,
# never the machine supervisor), imports gc_pack/leonard into a rig with a
# scripted stub agent (tool/test_fixtures/gc_sandbox_city), boots the
# LeonardBinding sample app on macOS, slings one bead per scenario with
# `--on leonard-drive`, and asserts what lands on the beads:
#
#   infra  a dead VM URI      leonard.verdict=infra, workflow fails
#   pass   sign in            leonard.verdict=pass, workflow passes
#   fail   a missing screen   leonard.verdict=fail, workflow fails, the
#                             check's stderr is in gc.attempt_log
#
# gc 1.5.0 runs a formula's [steps.check] on its ralph path, which treats
# exit 75 like any other failure: no attempt-free re-run. The infra scenario
# pins that; if a gc release starts re-running it, the scenario fails and says
# so.
#
# Environment:
#   LEONARD_GC_E2E_MODEL     leonard tier for the drives (default qwen-mlx)
#   LEONARD_GC_E2E_MODEL_ID  exact model id (default: the tier's)
#   LEONARD_GC_E2E_VM_URI    drive an already-running sample app instead of
#                            booting a fresh one per scenario (the scenarios
#                            assume its login screen)
#   LEONARD_GC_E2E_KEEP=1    keep the sandbox directory for inspection
#   LEONARD_GC_E2E_CACHE     pinned-binary cache (default ~/.cache/leonard-gc-e2e)
# Model credentials are passed to the drives through the sandbox's operator env
# file: SWIFT_INFER_AGENT_TOKEN, SWIFT_INFER_ENDPOINT, SWIFT_INFER_MODEL,
# ANTHROPIC_API_KEY, OPENAI_API_KEY (whichever are set).
#
# Exit: 0 every scenario as expected, 1 otherwise, 64 usage.

GC_VERSION=1.5.0
BD_VERSION=1.3.1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE="$REPO/tool/test_fixtures/gc_sandbox_city"
SAMPLE_APP="$REPO/packages/leonard_flutter/example/sample_app"
MODEL="${LEONARD_GC_E2E_MODEL:-qwen-mlx}"
CACHE="${LEONARD_GC_E2E_CACHE:-$HOME/.cache/leonard-gc-e2e}"

say() { printf 'gc_pack_e2e: %s\n' "$*" >&2; }
die() {
  say "$*"
  exit 1
}

SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -gt 0 ] || SCENARIOS=(infra pass fail)
for s in "${SCENARIOS[@]}"; do
  case "$s" in
    infra | pass | fail) ;;
    *)
      say "unknown scenario: $s (infra, pass, fail)"
      exit 64
      ;;
  esac
done

# ----- prerequisites -------------------------------------------------------
[ "$(uname -s)" = Darwin ] || die "macOS only: the sample app runs as a macOS desktop app"
for tool in dart flutter dolt tmux python3 curl shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required on PATH"
done
case "$(uname -m)" in
  arm64) ARCH=arm64 GC_SHA=e276f0a20a5e196d6bb9ab205824b1290e1ea5d929c907afa072bc704952861b BD_SHA=508ba807996e2b9c992c538a6f405f2fc7d2e16cf8b4e5b0d1bf9fe860367007 ;;
  x86_64) ARCH=amd64 GC_SHA=7ee60580a23fc3afeed83bcd149106cb921120dbeebd85922da3112b357ca185 BD_SHA=13bddb0b4774503d97d57e94204acc2b7c6b775fecc22fa38bc1b831718e234d ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac
if [ "$MODEL" = qwen-mlx ]; then
  endpoint="${SWIFT_INFER_ENDPOINT:-http://localhost:8080}"
  curl -fsS -m 5 -H "Authorization: Bearer ${SWIFT_INFER_AGENT_TOKEN:-}" "$endpoint/v1/models" >/dev/null ||
    die "swift-infer is not reachable at $endpoint (set SWIFT_INFER_ENDPOINT / SWIFT_INFER_AGENT_TOKEN)"
fi

fetch() {
  # fetch <name> <url> <sha256> -> path of the extracted binary <name>
  local dir="$CACHE/$1-$4"
  if [ ! -x "$dir/$1" ]; then
    mkdir -p "$dir"
    curl -fsSL -o "$dir/archive.tar.gz" "$2"
    printf '%s  %s\n' "$3" "$dir/archive.tar.gz" | shasum -a 256 -c - >/dev/null ||
      die "checksum mismatch for $2"
    tar -xzf "$dir/archive.tar.gz" -C "$dir" "$1"
    rm -f "$dir/archive.tar.gz"
  fi
  printf '%s' "$dir/$1"
}
GC_BIN="$(fetch gc "https://github.com/gastownhall/gascity/releases/download/v$GC_VERSION/gascity_${GC_VERSION}_darwin_$ARCH.tar.gz" "$GC_SHA" "$GC_VERSION")"
BD_BIN="$(fetch bd "https://github.com/gastownhall/beads/releases/download/v$BD_VERSION/beads_${BD_VERSION}_darwin_$ARCH.tar.gz" "$BD_SHA" "$BD_VERSION")"

# ----- sandbox -------------------------------------------------------------
# A short root keeps the controller socket path under the 100-byte limit.
ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lgce.XXXXXX")" && pwd -P)"
CITY="$ROOT/city"
CONTROLLER_PID=""
APP_PID_FILE=""
FAILURES=0

teardown() {
  set +e
  if [ -n "$CONTROLLER_PID" ]; then
    (cd "$CITY" && sx gc stop "$CITY" --timeout 60s) >>"$ROOT/teardown.log" 2>&1
    kill "$CONTROLLER_PID" 2>/dev/null
    wait "$CONTROLLER_PID" 2>/dev/null
  fi
  stop_app
  # Only sandbox processes carry $ROOT on their command line.
  pkill -TERM -f "$ROOT" 2>/dev/null
  sleep 1
  pkill -KILL -f "$ROOT" 2>/dev/null
  rm -f "$ROOT/operator.env"
  if [ "${LEONARD_GC_E2E_KEEP:-}" = 1 ]; then
    say "kept sandbox at $ROOT"
  else
    case "$ROOT" in
      */lgce.??????) rm -rf -- "$ROOT" ;;
    esac
  fi
}
trap teardown EXIT
trap 'exit 130' INT TERM

mkdir -p "$ROOT/bin" "$ROOT/gchome/.dolt" "$ROOT/runtime/tmux" "$ROOT/tmp" "$ROOT/rig"
ln -s "$GC_BIN" "$ROOT/bin/gc"
ln -s "$BD_BIN" "$ROOT/bin/bd"
# gc must never reach the machine's service manager from here.
for s in launchctl systemctl; do
  printf '#!/bin/sh\nexit 1\n' >"$ROOT/bin/$s"
  chmod +x "$ROOT/bin/$s"
done
printf '{"user.name":"gc-e2e","user.email":"gc-e2e@local"}\n' >"$ROOT/gchome/.dolt/config_global.json"
printf '[user]\n\tname = gc-e2e\n\temail = gc-e2e@local\n[beads]\n\trole = maintainer\n[safe]\n\tdirectory = *\n' >"$ROOT/gitconfig"

sx() {
  # sx <cmd...>: run with the sandbox's environment only. env -i drops any
  # GC_*/BEADS_* a live city session would leak into this shell.
  env -i HOME="$HOME" USER="${USER:-gc-e2e}" LANG=en_US.UTF-8 TERM=dumb TMPDIR="$ROOT/tmp" \
    PATH="$ROOT/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    GC_HOME="$ROOT/gchome" GC_ISOLATED=1 XDG_RUNTIME_DIR="$ROOT/runtime" TMUX_TMPDIR="$ROOT/runtime/tmux" \
    DOLT_ROOT_PATH="$ROOT/gchome" GIT_CONFIG_GLOBAL="$ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    GC_BIN="$ROOT/bin/gc" BEADS_DOLT_AUTO_START=0 GC_DISABLE_USAGE_METRICS=1 DO_NOT_TRACK=1 "$@"
}

rig_bd() { (cd "$CITY" && sx gc bd --rig sample "$@"); }

json() {
  # json <python expression over d> < json -> printed result
  python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "issues" in d:
    d = d["issues"]
print(eval(sys.argv[1]))
' "$1"
}

# The drives' leonard_cli runs from this checkout; the operator env file gives
# it dart, flutter and whichever credentials this shell has.
DART="$(command -v dart)"
printf '#!/bin/bash\nexec "%s" run "%s/packages/leonard_cli/bin/leonard_cli.dart" "$@"\n' "$DART" "$REPO" >"$ROOT/bin/leonard_cli"
chmod +x "$ROOT/bin/leonard_cli"
(
  umask 077
  printf 'PATH=%q:%q:"$PATH"\n' "$(dirname "$DART")" "$(dirname "$(command -v flutter)")"
  for name in SWIFT_INFER_AGENT_TOKEN SWIFT_INFER_ENDPOINT SWIFT_INFER_MODEL ANTHROPIC_API_KEY OPENAI_API_KEY; do
    if [ -n "${!name:-}" ]; then printf '%s=%q\n' "$name" "${!name}"; fi
  done
) >"$ROOT/operator.env"

say "sandbox at $ROOT (gc $GC_VERSION, bd $BD_VERSION, model $MODEL)"
sx gc init --file "$FIXTURE/city.init.toml" --name "lgce-$$" --no-start --skip-provider-readiness "$CITY" >"$ROOT/init.log" 2>&1 ||
  die "gc init failed: $(tail -5 "$ROOT/init.log")"
cp -R "$FIXTURE/packs" "$CITY/packs"
cat >>"$CITY/city.toml" <<EOF

[[rigs]]
name = "sample"

[rigs.imports.leonard]
source = "$REPO/gc_pack/leonard"

[rigs.imports.stub]
source = "./packs/stub"

[rigs.formula_vars]
leonard_cli = "$ROOT/bin/leonard_cli"
env_file = "$ROOT/operator.env"
EOF
printf '\n[[rig]]\nname = "sample"\npath = "%s/rig"\n' "$ROOT" >>"$CITY/.gc/site.toml"
(cd "$CITY" && sx gc import install) >>"$ROOT/init.log" 2>&1 || die "gc import install failed: $(tail -5 "$ROOT/init.log")"

(cd "$CITY" && sx gc start --foreground "$CITY") >"$ROOT/controller.log" 2>&1 &
CONTROLLER_PID=$!
for _ in $(seq 1 60); do
  grep -q 'Controller started' "$ROOT/controller.log" && break
  kill -0 "$CONTROLLER_PID" 2>/dev/null || die "controller exited: $(tail -5 "$ROOT/controller.log")"
  sleep 2
done
grep -q 'Controller started' "$ROOT/controller.log" || die "controller did not start: $(tail -5 "$ROOT/controller.log")"

# ----- the app -------------------------------------------------------------
# Each app scenario gets a freshly booted sample app, so it starts on the
# login screen whatever the previous drive did to it.
VM_URI=""
boot_app() {
  if [ -n "${LEONARD_GC_E2E_VM_URI:-}" ]; then
    VM_URI="$LEONARD_GC_E2E_VM_URI"
    return
  fi
  stop_app
  APP_PID_FILE="$ROOT/app.pid"
  rm -f "$ROOT/app.uri"
  say "  booting the sample app on macOS"
  (cd "$SAMPLE_APP" && dart run "$REPO/packages/leonard_cli/bin/leonard_drive.dart" up --runner flutter -d macos -t lib/main.dart \
    --timeout 300 --uri-file "$ROOT/app.uri" --pid-file "$APP_PID_FILE") >>"$ROOT/app.log" 2>&1 &
  for _ in $(seq 1 180); do
    [ -s "$ROOT/app.uri" ] && break
    sleep 2
  done
  [ -s "$ROOT/app.uri" ] || die "the sample app did not boot: $(tail -5 "$ROOT/app.log")"
  VM_URI="$(cat "$ROOT/app.uri")"
}
stop_app() {
  if [ -n "$APP_PID_FILE" ] && [ -f "$APP_PID_FILE" ]; then
    dart run "$REPO/packages/leonard_cli/bin/leonard_drive.dart" down --pid-file "$APP_PID_FILE" >/dev/null 2>&1 || true
    rm -f "$APP_PID_FILE"
  fi
}

# ----- scenarios -----------------------------------------------------------
check() {
  # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    say "  ok   $1 = $2"
  else
    say "  FAIL $1 = $2, want $3"
    FAILURES=$((FAILURES + 1))
  fi
}

run_scenario() {
  # run_scenario <name> <goal> <wall-clock-minutes> <expect-verdict> <expect-outcome> <metadata...>
  local name="$1" goal="$2" minutes="$3" verdict="$4" outcome="$5"
  shift 5
  say "scenario $name"
  local input
  input="$(rig_bd create "e2e $name" -d "$goal" --json 2>/dev/null | json 'd["id"] if isinstance(d, dict) else d[0]["id"]')"
  local meta=(--set-metadata "leonard.model=$MODEL" --set-metadata "leonard.wall_clock_minutes=$minutes")
  if [ -n "${LEONARD_GC_E2E_MODEL_ID:-}" ]; then meta+=(--set-metadata "leonard.model_id=$LEONARD_GC_E2E_MODEL_ID"); fi
  for kv in "$@"; do meta+=(--set-metadata "$kv"); done
  rig_bd update "$input" "${meta[@]}" >/dev/null 2>&1
  local workflow
  workflow="$(cd "$CITY" && sx gc sling sample/stub.driver "$input" --on leonard-drive --json 2>/dev/null | json 'd["workflow_id"]')"
  [ -n "$workflow" ] || die "sling failed for $name"

  local deadline=$((SECONDS + minutes * 60 + 300)) status=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    status="$(rig_bd show "$workflow" --json 2>/dev/null | json '(d[0] if isinstance(d, list) else d)["status"]')"
    [ "$status" = closed ] && break
    sleep 3
  done
  check "$name: workflow $workflow status" "$status" closed
  if [ "$status" != closed ]; then
    say "  sessions:"
    (cd "$CITY" && sx gc session list) 2>&1 | sed 's/^/    /' >&2 || true
    say "  controller log tail:"
    tail -20 "$ROOT/controller.log" | sed 's/^/    /' >&2
  fi

  local root input_json control
  root="$(rig_bd show "$workflow" --json 2>/dev/null)"
  input_json="$(rig_bd show "$input" --json 2>/dev/null)"
  control="$(rig_bd list --all --json --limit=0 2>/dev/null | json "next((b.get('metadata') or {}).get('gc.attempt_log', '[]') for b in d if (b.get('metadata') or {}).get('gc.root_bead_id') == '$workflow' and (b.get('metadata') or {}).get('gc.kind') == 'ralph'), '[]')")"
  check "$name: workflow gc.outcome" "$(json '((d[0] if isinstance(d, list) else d).get("metadata") or {}).get("gc.outcome", "")' <<<"$root")" "$outcome"
  check "$name: leonard.verdict" "$(json '((d[0] if isinstance(d, list) else d).get("metadata") or {}).get("leonard.verdict", "")' <<<"$input_json")" "$verdict"
  check "$name: check attempts" "$(json 'len(d)' <<<"$control")" 1
  say "  check stderr: $(json "d[-1].get('reason', '')[:300].replace(chr(10), ' / ') if d else '(none)'" <<<"$control")"
  check "$name: attempt log carries the verdict" "$(json "str('leonard-drive: $verdict' in d[-1].get('reason', '')) if d else 'False'" <<<"$control")" True
  local trajectory
  trajectory="$(json '((d[0] if isinstance(d, list) else d).get("metadata") or {}).get("leonard.trajectory", "")' <<<"$input_json")"
  check "$name: trajectory written" "$([ -s "$trajectory" ] && echo yes || echo no)" yes
}

for s in "${SCENARIOS[@]}"; do
  case "$s" in
    infra)
      run_scenario infra "Sign in to the app" 1 infra fail "leonard.vm_uri=ws://127.0.0.1:1/ws"
      ;;
    pass)
      boot_app
      run_scenario pass "Sign in with email demo@example.com and password password, and confirm the home screen shows you are signed in." \
        6 pass pass "leonard.vm_uri=$VM_URI" "leonard.done_evidence=Signed in"
      ;;
    fail)
      boot_app
      run_scenario fail "Open the Billing screen and confirm the invoice total is 42.00 dollars." \
        3 fail fail "leonard.vm_uri=$VM_URI" "leonard.done_evidence=Invoice total"
      ;;
  esac
done

if [ "$FAILURES" -gt 0 ]; then
  say "$FAILURES check(s) failed; controller log: $ROOT/controller.log (rerun with LEONARD_GC_E2E_KEEP=1 to keep it)"
  exit 1
fi
say "all scenarios as expected"
