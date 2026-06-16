---
name: leonard-pilot
description: >
  Drive a running Flutter app TURN-BY-TURN as the decider yourself — observe →
  decide → act — over Leonard's VM-service tool surface via
  `leonard_cli:leonard_drive`. Use when YOU should choose each tap/scroll, not
  Leonard's built-in LLM (for that, use leonard-driver). Requires a
  Leonard-instrumented app + its VM ws:// URI. No model API keys.
tools: Bash, Read
---

# leonard-pilot

Drive the user's running Flutter app to accomplish a **goal** by choosing each
action yourself. You see the app only through the structured observation the
helper returns; you act only via its tools. See the `drive-flutter-app` skill
for setup.

## Inputs
- **Goal** — what to accomplish.
- **VM URI** — `ws://127.0.0.1:PORT/TOKEN/ws` of the running app (convert from
  the `http://…/TOKEN/` form). If absent, STOP and ask.

## Helper (stateless: connect → one op → disconnect, JSON to stdout)
```bash
DRIVE="dart run leonard_cli:leonard_drive"
$DRIVE tools   --vm-uri "$VM"                       # available tools, once
$DRIVE observe --vm-uri "$VM"                       # current observation
$DRIVE invoke  --vm-uri "$VM" --tool core.tap --args '{"node_id":12}'
```
Trim observe output with jq to keep context small, e.g. only actionable nodes:
`... observe ... | jq -c '{route:.observation.core.routeStack, nodes:[.observation.core.nodes|to_entries[].value|select((.actions//[])|length>0)|{id,role,label,actions,state,scroll}]}'`

## The loop
1. `tools` once. 2. `observe` — read `routeStack`, nodes (id/role/label/
   actions/state, and `scroll:{pos,min,max}` on scrollables). 3. Decide the
   single next action. 4. `invoke` it; check `result.ok`. 5. `observe` again to
   confirm the change. Repeat until the goal's success state is visible, then
   report.

## Action rules
- Target nodes by **integer** `node_id` from the CURRENT observation whose
  `actions` permit it. Core tools + required args: `core.tap {node_id}`,
  `core.long_press {node_id}`, `core.enter_text {node_id, text}`,
  `core.scroll {node_id, axis:"vertical"|"horizontal", delta_pixels}`
  (read the node's `scroll` — move ~`max - pos` further; `pos == max` = at the
  bottom), `core.gesture {node_id, kind}`, `core.inspect_widget {node_id}`,
  `core.wait {seconds}`, `core.system_back {}`, `core.done {reason}`.
- **Never repeat an action that just failed** — read `result.error` (it names
  the bad field) and change something. One `invoke` per turn; `observe`
  between actions.
- Report: whether the goal was reached, the final route/state, and any failed
  actions with their errors.
