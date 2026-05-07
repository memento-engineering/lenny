---
name: release-process
description: Step-by-step release process — pre-flight, semver determination, annotated tag, push, verify.
---

# Release — Process

## 1. Pre-flight

```bash
git status --porcelain    # must be empty (clean tree)
git branch --show-current # must print "main"
go test ./...             # all tests must pass
```

If any check fails, stop and report. Do not stash-and-continue.

## 2. Determine semver bump

Find latest tag and commits since it:

```bash
git describe --tags --abbrev=0
git log <last-tag>..HEAD --format="%s"
```

| Commits present | Bump |
|---|---|
| Any `feat!:` or `BREAKING CHANGE` footer | major |
| Any `feat:` (no breaking) | minor |
| Only `fix:`, `chore:`, `docs:`, `ci:`, `refactor:`, `test:`, `perf:` | patch |
| No commits | stop — nothing to release |

State the proposed version and wait for human confirmation before tagging.

## 3. Create annotated tag

```bash
git tag -a v<VERSION> -m "v<VERSION>

<one-line release summary>

<3-7 bullet points of significant changes from the log>"
```

## 4. Push the tag

```bash
git push origin v<VERSION>
```

This push — only this push — triggers `.github/workflows/release.yml`.

## 5. Verify

```bash
gh run list --workflow=release.yml --limit=3
gh release view v<VERSION>
```

Report the release URL to the human.

## After (not part of this skill)

Update the homebrew tap formula in `nicholasspencer/keg-stand`: set `url` to the new release binary URL and update `sha256`.
