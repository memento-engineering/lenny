name: root-cause-tracing
description: Use when a bug manifests deep in the call stack — trace backward to find the original trigger instead of fixing at the symptom point

# Root Cause Tracing

## Overview

Bugs often manifest deep in the call stack. Your instinct is to fix where the error appears, but that's treating a symptom.

**Core principle:** Trace backward through the call chain until you find the original trigger, then fix at the source.

## When to Use

- Error happens deep in execution (not at entry point)
- Stack trace shows long call chain
- Unclear where invalid data originated
- Need to find which test/code triggers the problem

## The Tracing Process

### 1. Observe the Symptom

```
Error: operation failed in /path/to/project/src/core
```

### 2. Find Immediate Cause

**What code directly causes this?**

```
operation(directory)  # called with invalid directory value
```

### 3. Ask: What Called This?

```
ManagerA.execute(directory)
  → called by ServiceB.initialize()
  → called by Controller.create()
  → called by test setup
```

### 4. Keep Tracing Up

**What value was passed?**
- `directory = ""` (empty string!)
- Empty string resolves to current working directory
- That's the source code directory, not the intended target

### 5. Find Original Trigger

**Where did the empty string come from?**

```
context = setupTest()    # Returns { workDir: "" }
Controller.create(context.workDir)  # Accessed before initialization!
```

**Root cause:** Variable accessed before setup completes.

## Adding Stack Traces

When you can't trace manually, add instrumentation:

```
# Before the problematic operation, log context:
log_to_stderr("DEBUG operation:", {
  directory: directory,
  cwd: get_current_directory(),
  env: relevant_env_vars,
  stack: capture_stack_trace(),
})
```

**Tips:**
- Log to stderr in tests (stdout may be captured or suppressed)
- Log BEFORE the dangerous operation, not after it fails
- Include context: directory, cwd, environment variables, timestamps
- Capture the full stack trace

**Run and filter:**
```bash
<test command> 2>&1 | grep 'DEBUG operation'
```

**Analyze stack traces:**
- Look for test file names
- Find the line number triggering the call
- Identify the pattern (same test? same parameter?)

## Key Principle

**NEVER fix just where the error appears.** Trace back to find the original trigger.

After finding the root cause:
1. Fix at source
2. Add validation at each layer the data passes through (see [defense-in-depth.md](defense-in-depth.md))
3. Result: bug becomes structurally impossible

## Stack Trace Tips

- **In tests:** Log to stderr, not the application logger (which may be suppressed)
- **Before operation:** Log before the dangerous operation, not after failure
- **Include context:** Directory, cwd, environment variables, timestamps
- **Capture stack:** Most languages have a way to capture the current call stack
