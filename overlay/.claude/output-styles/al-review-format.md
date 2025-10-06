---
name: al-review-format
description: Formats AL code review results with severity indicators and actionable fixes for Business Central
---

When presenting AL code review findings, follow this format:

## Structure

1. **Summary Header**
   - Total issues found by severity
   - Files reviewed count
   - Review method (Codex + Validation)

2. **Issues by Severity**
   Group issues in this order:
   - 🔴 **Critical** - Breaks compilation, security vulnerabilities, data loss risks
   - 🟠 **High** - AL guideline violations, AppSourceCop errors, performance issues
   - 🟡 **Medium** - Code quality, maintainability, minor guideline deviations
   - 🔵 **Low** - Suggestions, optimizations, documentation improvements

3. **Issue Format**
   ```
   [severity] file.al:line - Issue description

   **Problem:** Clear explanation of what's wrong
   **Fix:** Specific code change or approach
   **Reason:** Why this matters for AL/Business Central
   ```

4. **Validation Indicators**
   - ✅ Validated against actual code
   - ⚠️ Needs review (context-dependent)
   - ❌ False positive (explain why)
   - 💡 Additional insight (beyond Codex)

5. **Footer Summary**
   - Quick action items
   - Files requiring most attention
   - Next steps

## Example Output

```
## AL Code Review Results

📊 **Summary**: 8 issues found in 3 files
- 🔴 Critical: 1
- 🟠 High: 3
- 🟡 Medium: 2
- 🔵 Low: 2

---

### 🔴 Critical Issues

**✅ NALICFConfigurationManagement.al:156** - Unguarded RecordRef.Field access
**Problem:** Field(FieldNo) called without checking if field exists
**Fix:** Add `if RecRef.FieldExist(FieldNo) then` guard
**Reason:** Runtime error if field doesn't exist in table

---

### 🟠 High Priority Issues

**✅ NALICFConfMapping.al:89** - Missing commit in write transaction
...
```

## Tone

- Direct and actionable
- Business Central terminology
- Assume AL development expertise
- Focus on "why" not just "what"

## Special Cases

- **Performance Issues**: Include estimated impact
- **Security Issues**: Reference BC security documentation
- **Breaking Changes**: Flag upgrade compatibility risks
- **AppSource Issues**: Cite specific AppSourceCop rules
