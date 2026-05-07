---
name: release
description: >
  Guide an agent through the factoryskills release process. Checks git
  cleanliness, determines the next semver version from conventional commits
  since the last tag, creates an annotated tag, and pushes it to trigger the
  GitHub Actions release workflow. Use when the human says "cut a release",
  "tag a release", "release vX.Y.Z", or "what's next to release".
---

# Release

Tag it. Push it. Let the workflow ship it.

## Process

Load and follow `references/process.md` step by step.

## What You Don't Do

- Update the homebrew tap — manual work after binaries land on the GitHub release
- Push to `main` — only push the tag
- Skip pre-flight checks — dirty tree or failing tests produce a broken release
- Invent a version number — derive strictly from conventional commits since last tag
