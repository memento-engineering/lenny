# Agent Operating Guide

This file is read once per session and pinned to the model's system prompt.
Adapt it to your app — the agent will read whatever you put here.

## What the agent sees each turn

- Running summary (your evolving understanding of the app state)
- Per-turn diff of the observation tree (core fragment + plugin fragments)
- Last N actions with their results

## Last N actions

The harness keeps a sliding window of the most recent actions and feeds it
back to the model so it can plan multi-step interactions. Default N is 10.

## Tools available

The merged tool list is regenerated each turn from the active plugin set.
Auto-disabled plugins disappear from the list mid-session.
