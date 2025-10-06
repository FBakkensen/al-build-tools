---
description: Review uncommitted AL code changes using OpenAI Codex with GPT-5 high reasoning
---

# AL Code Review with Codex

Review uncommitted AL/Business Central code changes using the `al-code-reviewer` agent.

This command:
1. Executes Codex CLI analysis with GPT-5 high reasoning
2. Validates Codex findings against actual code
3. Filters false positives and adds Business Central context
4. Returns actionable, severity-ranked feedback

**Usage:**
- `/al-codex-review` - Review all uncommitted AL changes
- `/al-codex-review --file <pattern>` - Review specific files (future enhancement)

---

!task al-code-reviewer "Review uncommitted AL code changes in this Business Central project. Check for AL coding guidelines, static analyzer compliance, BC best practices, and code quality issues. Provide validated, actionable feedback with severity levels."
