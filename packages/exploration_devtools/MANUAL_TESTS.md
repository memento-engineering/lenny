# Manual smoke checklist — exploration_devtools

Steps a human runs by hand for things automated tests cannot reach
(real network endpoints, real model providers).

All smokes in this file target **in-DevTools mode** (compiled bundle in a
real DevTools instance attached to a running app) — they exercise the real
binding handshake and real provider calls. For fast iteration on widgets,
layout, or form behavior that does not need real DTD/VM traffic, use
**standalone web mode** instead; see
[README.md -> "Iterating on the panel"](README.md#iterating-on-the-panel).

## Manual: Anthropic — Claude trajectory parity (lenny-0wd)

Goal: verify that starting a session from the DevTools prompt panel with
a real Anthropic API key + a Claude model produces the same trajectory
shape as the CLI flow.

Steps:

1. Build the extension: `tool/build_devtools_extension.sh` (or equivalent).
2. Launch a Flutter app that exposes `ExplorationBinding` and open
   DevTools → Exploration tab.
3. In the Prompt panel:
   - Provider: `anthropic`.
   - API key: a real ANTHROPIC key (will be persisted in workspace state).
   - Default model id: `claude-sonnet-4-6`.
4. Click "Test connection" — expect "OK (N models)".
5. Enter a small goal (e.g. "tap the first ListTile and report what you see").
6. Click Start. Wait for SessionEnded.
7. Compare the timeline panel's TurnRecord shape against
   `dart run exploration_cli --goal "..." --model claude-sonnet-4-6`
   running against the same app. Verify each TurnRecord has the same
   keys (action.tool, action.args, validation, observation diff).

PASS criteria:
- Models dropdown shows `claude-sonnet-4-6` with a `vision` badge.
- Trajectory turns are non-empty.
- No bearer token / api key appears in DevTools console logs.

## Manual: swift-infer admin-API capture (lenny-0wd)

Goal: verify that starting a session from the panel with swift-infer
(real Bearer token, captureBodies on) reaches the model AND the
conversation appears under `GET /v1/conversations/<id>` via the
swift-infer admin API.

Steps:

1. Start a local swift-infer gateway with a known
   `SWIFT_INFER_AGENT_TOKEN`.
2. In the Prompt panel:
   - Provider: `swift-infer`.
   - Bearer token: paste the token (masked).
   - Endpoint: `http://localhost:8080` (or your gateway URL).
   - Capture bodies: ON (default).
   - Default model id: `qwen3.6-35b-a3b-8bit`.
3. Click "Test connection" — expect either real model list or "using
   fallback list" badge.
4. Enter a small goal. Note the conversationId breadcrumb in the panel
   (e.g. `exploration-panel-<base36>`); copy it.
5. Click Start. Wait for SessionEnded (or stop after a few turns).
6. From a terminal: `curl -H "Authorization: Bearer $TOKEN" \
   http://localhost:8080/v1/conversations/<conversationId>`.

PASS criteria:
- The admin-API response contains at least one captured turn with
  request + response bodies.
- The response shows `Authorization: Bearer` (NOT `x-api-key`).
- Headers include `X-Conversation-Id` and `X-Swift-Infer-Capture-Bodies:
  true`.
- No bearer token leaks into DevTools console logs.

## Manual: Provider config persistence across DevTools reloads (lenny-r8f)

Goal: verify that provider config (bearer token, base URL, model id) survives
a DevTools reload without re-entry.

Prerequisite: in-DevTools mode with a real DTD connection (i.e., a running app
with `ExplorationBinding.ensureInitialized()` attached in Chrome DevTools).

Steps:

1. Build and open the DevTools extension in a real DevTools instance.
2. In the Prompt panel, configure any provider (e.g. swift-infer: bearer token +
   endpoint; or anthropic: API key).
3. Reload DevTools (browser Refresh / DevTools reload button).
4. Re-open the Exploration extension → Prompt panel.

PASS criteria:
- Previously entered values re-render (secrets masked as ****) without prompting
  for re-entry.
- Config survives a `flutter hot restart` of the target app (DTD stays connected).

Secret-storage note (DTD 4.x has no encrypted store):
Config JSON — including unredacted bearer tokens and API keys — is written to
plain-text files at:
  <workspace_root>/.dart_tool/lenny.providerConfig.<providerId>.json
These are local-machine files equivalent to `.env` or `~/.netrc`. Do not commit
them to version control (add `lenny.providerConfig.*` or `.dart_tool/` to
`.gitignore`). Rotate credentials after sessions where these are high-value.
