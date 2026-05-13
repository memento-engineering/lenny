---
name: concreteness
version: 2
---

## Summary

Concreteness measures how literal the spec's plan is. Every step should name an exact file path, an exact function or symbol, an exact command, and the expected output. Low concreteness forces the builder to redo discovery: pick which file to edit, infer argument shapes, guess at expected behavior. The cost is misaligned implementations, non-idiomatic code, and rework. A spec can be short and still score A; a spec can be long and still score F. Length does not buy concreteness — naming does.

This rubric grades the *literal-vs-vague* axis only. A spec that names every file but leaves three valid designs on the table is failing a different axis (see `decision-density.md`). Grade what the words on the page actually say to do.

## Grades

### A

Every step names exact files, exact functions, exact commands with expected output. No "appropriate", "as needed", "similar to", "wire it up". A reader can predict the diff before reading the code.

**Verify against the repo.** Every named symbol, file path, package, or command in a step must either (a) resolve in the current repo via `grep -rn '<symbol>' .` / `rg '<symbol>'` / `find . -path '<file>'`, or (b) be explicitly marked as new — created by this bead's own diff, or by a sibling bead that this bead has an explicit `bd dep` on. A spec that names `internal/foo/Bar` where neither the package nor the function exists, and the spec does not announce them as new, is not A. "Literal-sounding" is not "literally correct."

### B

Most steps are literal; a handful use shorthand (a glob, a referenced existing pattern, an "and the same for the symmetric case") that is unambiguous given the surrounding context. The shorthand reads as economy, not vagueness.

### C

Roughly half the steps need the builder to infer file paths, argument shapes, or expected output. The plan tells you *what* to change but you have to find *where*; or it tells you *where* but you have to choose the function signature.

### D

Judgment calls about what file/function/command to use are scattered throughout. The plan reads like an outline: every step is a paragraph the builder must turn into commits, and many require independent discovery before the work itself can start.

### F

The spec describes the goal, not the work. The builder essentially has to redo discovery and produce the implementation plan that the spec was supposed to provide. Phrases like "make the CLI nicer", "improve error handling", "add tests for this area" anchor an F.

## Examples

### Example: factoryskills-vo1 — per-subcommand `--help` framework (A)

This bead exemplifies A-grade concreteness. The plan does not say "add a help guard"; it shows the exact Go code:

```
func helpFlag(args []string) bool {
    for _, a := range args {
        if a == "--help" || a == "-h" {
            return true
        }
    }
    return false
}

type subcommand struct {
    run  func([]string) error
    help string
}
```

It names the file (`cmd/fs/main.go`), the new types (`subcommand`, `commandTable`, `deprecatedAliases`), the dispatch order ("top-level help → alias resolution → table lookup → per-command help guard → handler"), and the test command (`go build -o /tmp/fs ./cmd/fs` → expect exit 0). Every step ends with a literal commit message. Grade: A — a reader can predict the diff before opening an editor.

### Example: factoryskills-cm3 — `fs init --dev` bin swap (A)

The bin-swap step names `os.Lstat(/opt/homebrew/bin/fs)`, branches on `info.Mode()&os.ModeSymlink == 0`, calls `os.Readlink`, compares to `repoBinPath`, and short-circuits when the symlink already points at the dev build. The literal Go is in the spec:

```
if info.Mode()&os.ModeSymlink == 0 {
    return fmt.Errorf("%w: %s is a regular file", ErrUnknownBinTarget, brewBinPath)
}
target, err := os.Readlink(brewBinPath)
```

A sentinel error is named (`ErrUnknownBinTarget`), the shell-out is exact (`brew unlink factoryskills`, `brew link --overwrite factoryskills`), and the expected output of each verification command is stated. Grade: A — every file path, function name, and expected output is literal.

### Example: factoryskills-dli — `fs init --help` body (A)

The plan does not say "write help text covering the flags". It quotes the entire literal help body inside a Go raw string, names the file (`cmd/fs/help.go`), points at the exact line range to replace ("the current stub `helpInit` constant (lines 8-16)"), and lists the required substrings the test must assert (`.beads`, `.factoryskills/config`, `.claude/skills`, `status.custom`, `draft,spec_review,ready,code_review,needs_work`, `does not touch hooks`). Every artifact `commands.Init` creates is named in the help body so the doc cannot drift from the code. Grade: A — every artifact named is the A-grade signal. The plan even pre-writes the test:

```
required := []string{
    "Usage: fs init",
    "--dev",
    "--hooks",
    ".beads",
    ...
}
```

### Example: anti-pattern — "wire it up similar to the other commands" (D/F)

Compare a synthesized D/F-grade snippet against vo1:

```
1. Add a help flag to each subcommand. Wire it up similar to the other
   flags so users can get help on each one. Add appropriate tests.
2. Update the top-level help to mention the new behavior.
```

This says nothing useful. Which file? Which function? What does "similar to the other flags" mean when the existing flags are inconsistent? What's the expected output of "appropriate tests"? Contrast vo1, which gives the literal `helpFlag` function, the literal `commandTable` map, the literal dispatch order, and the literal test invocation. The anti-pattern forces the builder to redo discovery; vo1 lets the builder commit. Grade: D if the rest of the plan partially compensates with named files; F if the whole spec reads at this altitude.

## Calibration

- **Before grading A or B, actually run `grep`/`rg`/`find` for at least one named symbol per step block.** If a step says "edit `internal/route/Decide`" and `rg 'func Decide' internal/route/` returns nothing, and the spec does not announce `Decide` as new, the grade is not A — drop to C or below depending on how many other steps share the same defect. Grep is cheap; awarding A on faith is the v1 leniency failure.
- If between A and B, err toward B when one step uses a glob like `internal/commands/*.go` instead of naming files, or refers to "the same pattern as `forge`" without quoting it. That's economy shorthand, not vagueness — but it is shorthand, so it's not a clean A.
- If between B and C, err toward C when more than half the named commands lack expected output (`go test ./internal/commands/` with no "expect PASS" or "expect `ok`" annotation). Naming the command without naming what success looks like means the builder still has to decide what passes.
- If between C and D, err toward D when the plan mentions a file once but the per-step instructions are still abstract ("update the dispatcher", "fix the parser") — naming the file is not enough if the change inside the file is left to inference.
- If between D and F, err toward F when the plan reads as goals ("make the CLI nicer", "improve error handling", "tighten up the prime output") rather than steps. Goal-shaped specs anchor F.
- If a spec is short and literal (like d2u, two string-literal edits with the exact before/after quoted), grade it on what is there, not on what is missing. Short-and-literal is A. Short-and-vague is F.
- Concreteness is about words on the page, not about the bead's complexity. A two-line bead that names two strings to change is A. A two-hundred-line bead that paraphrases the goal of every step is F.
- **On a re-deliberation round** (the bead carries a prior `inspector: REBUILD.`, `inspector: RESPEC.`, or `inspector: DECOMPOSE.` verdict comment — see the re-deliberation step in `agents/critique.md`), the implementation revealed how the spec held up. Read the branch diff and the verdict. Downgrade if you can point to (a) a step that didn't survive contact with the code — the literal command or symbol named in the spec did not exist or behaved differently, (b) an acceptance criterion that proved unsatisfiable as written, or (c) a missed cross-file dependency the spec did not name. A spec that graded A on words-on-the-page but whose Step 3 named a function the codebase didn't expose is no longer A on this round — concreteness is the literal-vs-vague axis, and the literal was wrong. Drop one grade band per defect class, capped at F. If the diff and verdict show the spec held up and the build slipped (a `REBUILD` verdict whose findings cite build-side issues only), the grade is unchanged.
