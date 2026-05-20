# Dogfood LaunchAgent Bootstrap

One-time setup to schedule the nightly swift-infer e2e run on your Mac.

## Prerequisites

- `dart` on PATH (via Flutter SDK)
- `bd` on PATH (beads CLI)
- `fs` on PATH (factoryskills CLI)
- swift-infer gateway running at your usual endpoint

## Step 1 — Create the secrets file

Create `~/.lenny-dogfood.env` (not committed):

    SWIFT_INFER_ENDPOINT=http://localhost:8080
    SWIFT_INFER_AGENT_TOKEN=sk-…

## Step 2 — Install the plist

From the repo root:

    REPO_ROOT="$(pwd)"
    sed \
      -e "s|REPO_ROOT_PLACEHOLDER|$REPO_ROOT|g" \
      -e "s|HOME_PLACEHOLDER|$HOME|g" \
      scripts/launchd/com.nicospencer.lenny.dogfood.plist \
      > ~/Library/LaunchAgents/com.nicospencer.lenny.dogfood.plist

## Step 3 — Bootstrap the agent

    launchctl bootstrap gui/$UID \
      ~/Library/LaunchAgents/com.nicospencer.lenny.dogfood.plist

## Step 4 — Verify

    launchctl print gui/$UID/com.nicospencer.lenny.dogfood

Should show `state = waiting`.

## Manual trigger

    launchctl kickstart -k gui/$UID/com.nicospencer.lenny.dogfood

## Remove

    launchctl bootout gui/$UID/com.nicospencer.lenny.dogfood
    rm ~/Library/LaunchAgents/com.nicospencer.lenny.dogfood.plist

## Tracking bead

`bd show lenny-g8y` — health label and state-change history.
