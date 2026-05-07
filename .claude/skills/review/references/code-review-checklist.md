name: code-review-checklist
description: Use during code review — structured checklist covering code quality, architecture, testing, requirements, and production readiness with example output

# Code Review Checklist

Load this reference when reviewing code changes for production readiness.

## Review Checklist

### Code Quality

- Clean separation of concerns?
- Proper error handling?
- Type safety (if applicable)?
- DRY principle followed?
- Edge cases handled?
- No secrets, credentials, or PII in the diff?

### Architecture

- Sound design decisions?
- Scalability considerations?
- Performance implications?
- Security concerns?
- Consistent with existing patterns?

### Testing

- Tests actually test logic (not mocks)?
- Edge cases covered?
- Integration tests where needed?
- All tests passing?
- Validation plan items covered?

### Requirements

- All acceptance criteria met?
- Implementation matches the plan?
- No scope creep?
- Breaking changes documented?

### Production Readiness

- Migration strategy (if schema changes)?
- Backward compatibility considered?
- No obvious bugs?
- Error messages are useful?

## Output Format

### Strengths

[What's well done? Be specific — file and line references.]

### Issues

#### Critical (Must Fix)

[Bugs, security issues, data loss risks, broken functionality, missing AC]

#### Important (Should Fix)

[Architecture problems, missing error handling, test gaps, plan deviation]

#### Suggestion (Nice to Have)

[Code style, optimization opportunities, naming improvements]

**For each issue:**
- File:line reference
- What's wrong
- Why it matters
- How to fix (if not obvious)

### Recommendations

[Improvements for code quality, architecture, or process]

### Assessment

**Ready to merge?** [Yes / With fixes / No]

**Reasoning:** [Technical assessment in 1-2 sentences]

## Critical Rules

**DO:**
- Categorize by actual severity (not everything is Critical)
- Be specific (file:line, not vague)
- Explain WHY issues matter
- Acknowledge strengths first
- Give a clear verdict
- Check every acceptance criterion against the diff

**DON'T:**
- Say "looks good" without checking
- Mark nitpicks as Critical
- Give feedback on code you didn't review
- Be vague ("improve error handling" — which error? where?)
- Avoid giving a clear verdict
- Rewrite the code — flag the issue, let the builder fix it

## Example Output

```
### Strengths
- Clean module structure with proper separation (internal/commands/, internal/lifecycle/)
- Comprehensive state machine with all transitions validated (lifecycle.go:19-41)
- Good use of conventional commits throughout

### Issues

#### Important
1. **Missing validation for empty title**
   - File: internal/commands/discover.go:33
   - Issue: Empty string check only after join — whitespace-only args pass through
   - Fix: Trim each arg before joining, or validate the joined result

2. **Branch name not URL-safe**
   - File: internal/project/project.go:85
   - Issue: Sanitization allows characters that break some git hosts
   - Fix: Restrict to [a-z0-9-] after lowercasing

#### Suggestion
1. **Status display order**
   - File: internal/commands/status.go:15-30
   - Issue: Statuses listed alphabetically, not by lifecycle progression
   - Impact: Minor UX — users expect draft → planned → ready flow

### Recommendations
- Add input validation tests for edge cases (empty, whitespace, special chars)
- Consider a status ordering constant in lifecycle.go

### Assessment

**Ready to merge: With fixes**

**Reasoning:** Core implementation is solid with good architecture. Important issues (title validation, branch sanitization) are straightforward fixes that don't affect the design.
```
