name: defense-in-depth
description: Use after finding a root cause — add validation at every layer data passes through to make the bug structurally impossible

# Defense-in-Depth Validation

## Overview

When you fix a bug caused by invalid data, adding validation at one place feels sufficient. But that single check can be bypassed by different code paths, refactoring, or mocks.

**Core principle:** Validate at EVERY layer data passes through. Make the bug structurally impossible.

## Why Multiple Layers

Single validation: "We fixed the bug"
Multiple layers: "We made the bug impossible"

Different layers catch different cases:
- Entry validation catches most bugs
- Business logic catches edge cases
- Environment guards prevent context-specific dangers
- Debug logging helps when other layers fail

## The Four Layers

### Layer 1: Entry Point Validation

**Purpose:** Reject obviously invalid input at API boundary

```
function create_project(name, working_directory):
  if not working_directory or working_directory.strip() == "":
    raise "working_directory cannot be empty"
  if not path_exists(working_directory):
    raise "working_directory does not exist: {working_directory}"
  if not is_directory(working_directory):
    raise "working_directory is not a directory: {working_directory}"
  # ... proceed
```

### Layer 2: Business Logic Validation

**Purpose:** Ensure data makes sense for this operation

```
function initialize_workspace(project_dir, session_id):
  if not project_dir:
    raise "project_dir required for workspace initialization"
  # ... proceed
```

### Layer 3: Environment Guards

**Purpose:** Prevent dangerous operations in specific contexts

```
function git_init(directory):
  # In tests, refuse git init outside temp directories
  if is_test_environment():
    if not directory.starts_with(temp_dir()):
      raise "Refusing git init outside temp dir during tests: {directory}"
  # ... proceed
```

### Layer 4: Debug Instrumentation

**Purpose:** Capture context for forensics

```
function git_init(directory):
  log_debug("About to git init", {
    directory: directory,
    cwd: current_directory(),
    stack: capture_stack(),
  })
  # ... proceed
```

## Applying the Pattern

When you find a bug:

1. **Trace the data flow** — where does bad value originate? Where is it used?
2. **Map all checkpoints** — list every point data passes through
3. **Add validation at each layer** — entry, business, environment, debug
4. **Test each layer** — try to bypass layer 1, verify layer 2 catches it

## Key Insight

All four layers are often necessary. During testing, each layer catches bugs the others miss:
- Different code paths bypass entry validation
- Mocks bypass business logic checks
- Edge cases on different platforms need environment guards
- Debug logging identifies structural misuse

**Don't stop at one validation point.** Add checks at every layer.
