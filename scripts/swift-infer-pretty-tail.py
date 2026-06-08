#!/usr/bin/env python3
"""Pretty live-tail of the swift-infer read API for ONE exploration run.

Follows a single conversation and prints, per turn, a compact view of what the
model *did* — its thinking gist + the tool call(s) it made — plus a one-line
health stamp (prompt size, latency, tok/s). It deliberately does NOT dump the
raw message arrays; just the new turn's distilled action.

Usage:
  # follow an explicit conversation id (a "trace id" for the whole run):
  swift-infer-pretty-tail.py exploration-cli-2026-06-08T01-52-19-...-1780883539782

  # or auto-latch onto the next run that starts after the script does:
  swift-infer-pretty-tail.py            # waits, then follows the newest conversation

  # replay an existing run and exit (no follow loop):
  swift-infer-pretty-tail.py <cid> --once

Env: SWIFT_INFER_ADMIN_TOKEN (admin bearer). BASE defaults to 127.0.0.1:8080.
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

BASE = os.environ.get("SWIFT_INFER_BASE", "http://127.0.0.1:8080")
TOKEN = os.environ.get("SWIFT_INFER_ADMIN_TOKEN", "")

# ANSI — kept simple so it reads well in a screen recording.
C = {
    "rule": "\033[38;5;244m", "cyan": "\033[1;36m", "dim": "\033[2m",
    "green": "\033[1;32m", "yellow": "\033[33m", "red": "\033[1;31m",
    "blue": "\033[34m", "reset": "\033[0m", "bold": "\033[1m",
}
SLOW_TOKS = 20.0  # tok/s below this is flagged — the shared-machine spike tell.


def _get(path):
    req = urllib.request.Request(
        BASE + path, headers={"Authorization": f"Bearer {TOKEN}"}
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def _q(path, **params):
    qs = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    return _get(f"{path}?{qs}" if qs else path)


def conv_requests(cid):
    """Request_ids for a conversation, oldest-first."""
    d = _q(f"/v1/conversations/{urllib.parse.quote(cid, safe='')}")
    return list(reversed([r["request_id"] for r in d.get("requests", [])]))


def recent_request_ids(limit=200):
    """Most-recent request_ids (newest first)."""
    d = _q("/v1/requests", limit=limit)
    return [r["request_id"] for r in d.get("requests", [])]


def find_new_conversation(baseline):
    """Latch onto the first request_id that is NOT in the start-time baseline
    and return its conversation_id. Timezone-independent (no clock math): we
    follow whichever run produces the first genuinely new request after the
    tail started."""
    for rid in recent_request_ids(50):
        if rid not in baseline:
            try:
                return _get(f"/v1/trace/{rid}")["request"]["conversation_id"]
            except Exception:
                continue
    return None


def fmt_args(args):
    if args is None:
        return ""
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            return args
    if isinstance(args, dict):
        return "{" + ", ".join(f"{k}: {v}" for k, v in args.items()) + "}"
    return str(args)


def short(s, n=140):
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def print_turn(idx, rid, trace):
    m = trace.get("metrics", {}) or {}
    r = trace.get("response", {}) or {}
    tps = m.get("tokens_per_sec") or 0.0
    dur = (m.get("total_duration_ms") or 0) / 1000.0
    ptok = m.get("prompt_tokens") or 0
    ts = (m.get("timestamp") or "")[11:19]
    slow = tps and tps < SLOW_TOKS
    tcol = C["red"] if slow else C["dim"]
    warn = "  ⚠ SLOW" if slow else ""

    print(f"{C['rule']}{'━'*60}{C['reset']}")
    print(f"{C['cyan']}turn {idx:<3}{C['reset']} "
          f"{C['dim']}{rid} · {ts}{C['reset']}  "
          f"{C['dim']}prompt {ptok} tok · {dur:.1f}s · {tcol}{tps:.1f} tok/s{C['reset']}"
          f"{C['red']}{warn}{C['reset']}")

    think = short(r.get("thinking_content", ""))
    if think:
        print(f"  {C['dim']}💭 {think}{C['reset']}")

    tcs = r.get("tool_calls") or []
    if not tcs:
        body = short(r.get("content", ""), 80)
        print(f"  {C['red']}🔧 (no tool call){C['reset']}"
              + (f"  {C['dim']}{body}{C['reset']}" if body else ""))
    for tc in tcs:
        name = tc.get("name", "?")
        print(f"  {C['green']}🔧 {name}{C['reset']}  "
              f"{C['blue']}{fmt_args(tc.get('arguments'))}{C['reset']}")
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("conversation_id", nargs="?", default=None)
    ap.add_argument("--once", action="store_true",
                    help="print existing turns and exit (replay, no follow)")
    ap.add_argument("--interval", type=float, default=1.5)
    args = ap.parse_args()

    if not TOKEN:
        print("error: SWIFT_INFER_ADMIN_TOKEN not set", file=sys.stderr)
        return 2

    # Force line-buffered stdout so each turn appears live (matters when the
    # output is captured by asciinema / a pipe rather than a bare TTY).
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    cid = args.conversation_id
    if not cid and not args.once:
        baseline = set(recent_request_ids(200))
        print(f"{C['yellow']}waiting for a new run to start…{C['reset']} "
              f"{C['dim']}(start the exploration_cli now){C['reset']}", flush=True)
        while not cid:
            cid = find_new_conversation(baseline)
            if not cid:
                time.sleep(args.interval)
    elif not cid:
        print("error: --once needs a conversation_id", file=sys.stderr)
        return 2

    print(f"{C['bold']}following{C['reset']} {C['cyan']}{cid}{C['reset']}\n", flush=True)
    seen = set()
    idle = 0
    while True:
        try:
            rids = conv_requests(cid)
        except Exception as e:
            print(f"{C['dim']}(poll error: {e}){C['reset']}")
            time.sleep(args.interval)
            continue
        new = [r for r in rids if r not in seen]
        for r in new:
            try:
                print_turn(len(seen), r, _get(f"/v1/trace/{r}"))
            except Exception as e:
                print(f"{C['dim']}(trace {r} error: {e}){C['reset']}")
            seen.add(r)
        if args.once and not new:
            break
        idle = idle + 1 if not new else 0
        if args.once and rids and idle >= 1:
            break
        time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
