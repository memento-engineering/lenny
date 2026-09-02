Drive the Leonard debug panel through this complete smoke. Do not call
`core.done` until every numbered assertion is visible.

Environment-value contract: when a field below names `${NAME}`, invoke
`core.enter_text` with the exact literal `${NAME}` as its `text`. The outer
harness resolves that exact action argument at dispatch, so the field then
DISPLAYS a different, resolved value — that difference is the success
state, not a failure. Once such a field is non-empty, never re-enter it and
never retype it. Never ask to see, repeat, infer, or report a resolved
runtime value.

Outer-action guard for this smoke: every `node_id` is a JSON integer copied
from the current observation, never a quoted string. When the observation has
no nodes, call only `core.wait {"seconds": 2}`; never invent a node id or call a
node-targeted tool. If vertical scrolling is genuinely required, call
`core.scroll {"node_id": 1, "axis": "vertical", "delta_pixels": 200}`, replacing
`1` with the visible scrollable node's integer id.
Correct any failed action before continuing.

1. Stay on Conversation and open Settings when the provider form is hidden.
2. Set Provider to `swift-infer`. Fill exactly three fields: Endpoint to
   `${SWIFT_INFER_ENDPOINT}`, Bearer token to `${SWIFT_INFER_AGENT_TOKEN}`,
   and Default model id to `${PANEL_SELFDRIVE_MODEL_ID}`. The picker labeled
   `Model` below them is empty until the connection is tested — leave it alone
   for now.
3. Press Test connection. Continue only after `OK (N models)` is visible with
   N greater than zero.
4. Look at the picker labeled `Model`. Continue only when it shows a non-empty
   selected model. While it is still empty, press the `Reload models` refresh
   button beside it, wait, and look again. Its selected value is a resolved
   runtime value: never read it back, compare it against anything you typed, or
   report it. The `Resolved model:` line beneath the picker is the same
   resolved runtime value under a different name: leave it alone too — never
   read it back, compare it, or quote it in `core.done`.
5. Enter this inner goal exactly into the panel's text field labeled `Goal` —
   the INNER goal for the panel's own session, not your Mission; typing it is
   one step, never completion: `Report the title of the current sample_app
   screen, then call done.`
6. Press Start. Continue only when `Stop` is visible where `Start` was: that is
   the panel's running state and the only proof Start was accepted. If
   `Select a model` appears under the `Model` picker instead, Start was refused
   — go back to step 4.
7. Open Timeline. Continue only after a row matching `#<index> <tool>(...)` is
   visible with a non-empty tool name.
8. Open that row. Under Proposed action, verify the tool is not `<unknown>`.
   Remember the row's index and tool, then return from the detail view.
9. Return to Conversation. If Stop is visible, press it; otherwise wait for the
   natural SessionEnded. Continue only when Start is visible, enabled, and
   tappable again.
10. Call `core.done` with a credential-free reason in this exact form, copying
    the index and tool from the Timeline row you actually observed: `panel
   smoke passed: inner turn <index> tool <tool>`. `core.done` is refused
   unless a row matching `#<index> <tool>(` is present in the current
   observation AND the index and tool you quote are that row's own.

done-reason-pattern: ^panel smoke passed: inner turn \d+ tool [A-Za-z0-9_.]+$
done-evidence-pattern: ^#([0-9]+) ([A-Za-z0-9_.-]+)\(
