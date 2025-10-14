---
description: Review uncommitted AL code changes using specialized agent for deep analysis beyond static analyzers
---

# AL Code Review

Use the `al-code-review-agent` (Claude Opus) to review uncommitted AL changes for issues that **static analyzers cannot catch**.

## Review Focus

**Business Logic & Design**:
- Incorrect business logic, missing validations, data integrity risks
- Breaking changes, architectural concerns, code placement anti-patterns

**BC Performance Patterns**:
- Missing SetLoadFields (9x performance gains possible)
- N+1 queries, expensive OnValidate triggers
- Partial records misuse (SetLoadFields before Insert/Delete/Rename)
- SIFT inefficiency, transaction management issues

**Security & Data Safety**:
- SQL injection, unvalidated input, missing permission checks
- Data loss risks, delete without confirmation

**Code Quality**:
- Complex logic, misleading names, code duplication

## Output Format

📊 **Summary**: X issues in Y files
- 🔴 Critical: Data loss, security, breaking changes
- 🟠 High: Performance, transactions, upgrade risks
- 🟡 Medium: Business logic, validations, complexity
- 🔵 Low: Duplication, naming, refactoring

**Report structure**: Severity-grouped issues with file:line, problem, fix, reason

---

## Execution

Launch the `al-code-review-agent` subagent to perform the review:

```
Use the Task tool to launch the al-code-review-agent with the following prompt:

"Review all uncommitted AL code changes in this repository.

Get uncommitted changes by running: git diff HEAD -- '*.al'

Analyze ONLY the changed lines (lines starting with + or -) and identify issues that static analyzers cannot catch.

Provide a structured report with:
- Summary of total issues by severity
- Detailed findings grouped by severity (Critical, High, Medium, Low)
- For each issue: file:line reference, problem description, fix suggestion, and Business Central-specific reasoning

Focus on: business logic errors, BC performance patterns (SetLoadFields, N+1 queries), security risks, and code quality issues."
```

After the agent completes its review, validate the findings against the current implementation context and provide actionable guidance to the user.
