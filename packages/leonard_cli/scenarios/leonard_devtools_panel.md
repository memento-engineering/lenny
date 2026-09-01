Drive the Leonard debug panel through this complete smoke. Do not call
`core.done` until every numbered assertion is visible.

Environment-value contract: when a field below names `${NAME}`, invoke
`core.enter_text` with the exact literal `${NAME}` as its `text`. The outer
harness resolves that exact action argument at dispatch; never ask to see,
repeat, infer, or report its runtime value.

Outer-action guard for this smoke: every `node_id` is a JSON integer copied
from the current observation, never a quoted string. When the observation has
no nodes, call only `core.wait {"seconds": 2}`; never invent a node id or call a
node-targeted tool. If vertical scrolling is genuinely required, call
`core.scroll {"node_id": 1, "axis": "vertical", "delta_pixels": 200}`, replacing
`1` with the visible scrollable node's integer id.
Correct any failed action before continuing.

1. Stay on Conversation and open Settings when the provider form is hidden.
2. Select provider `swift-infer`. Set Endpoint to `${SWIFT_INFER_ENDPOINT}`,
   Bearer token to `${SWIFT_INFER_AGENT_TOKEN}`, and Default model id to
   `${PANEL_SELFDRIVE_MODEL_ID}`. Select that model in the model dropdown.
3. Press Test connection. Continue only after `OK (N models)` is visible with
   N greater than zero.
4. Enter this inner goal exactly: `Report the title of the current sample_app
   screen, then call done.`
5. Press Start and wait for the panel session to emit a completed turn.
6. Open Timeline. Continue only after a row matching `#<index> <tool>(...)` is
   visible with a non-empty tool name.
7. Open that row. Under Proposed action, verify the tool is not `<unknown>`.
   Remember the row's index and tool, then return from the detail view.
8. Return to Conversation. If Stop is visible, press it; otherwise wait for the
   natural SessionEnded. Continue only when Start is visible, enabled, and
   tappable again.
9. Call `core.done` with a credential-free reason of the form
   `panel smoke passed: inner turn <index> tool <tool>`.
