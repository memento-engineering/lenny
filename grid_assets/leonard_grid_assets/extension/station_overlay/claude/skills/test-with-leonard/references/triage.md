# Triage a failed Leonard E2E run

Begin with the `e2e` Command's structured JSON. Read `status`,
`failure_codes`, `driver_exit_status`, `trajectory_path`,
`provider_request_id`, `model`, and `expectation_evidence`. The typed
trajectory is the verdict source; never infer PASS or FAIL from child stdout or
stderr, even when that prose claims a result.

Classify the smallest reproducible failure:

1. Harness or setup: preflight, launch, missing trajectory, malformed
   trajectory, or invalid typed-record shape failures. An extension-disabled
   event or a typed action failure produced from valid tool arguments is a
   harness/extension defect.
2. Model behaviour: a structurally valid run with malformed tool arguments, no
   tool call, a repeated target/action, or a typed non-`done` footer, unless the
   deterministic evidence identifies a harness failure instead.
3. Goal under-specification: credentials, an otherwise unknowable target, or
   observable success evidence was omitted from the goal, or the requested
   success state cannot be observed by the enabled extensions.

For `qwen-mlx`/swift-infer model failures, use the existing `debug-inference`
skill. Look up the captured gateway request and response by
`provider_request_id` when it is present. When it is absent, use the
`trajectory_path` timestamps and the verdict's trajectory time window. Compare
the captured request/response, including raw tool-call arguments and content,
with the typed trajectory before assigning a cause.

File one bead for each distinct defect. Include the `trajectory_path`,
`provider_request_id` when present, all `failure_codes`, the classification,
and the smallest scenario that reproduces it. Do not combine unrelated
failures or retrofit them onto an existing fix.
