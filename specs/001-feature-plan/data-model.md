## Data Model
No persistent domain entities introduced. Transient in-memory structures only:

- FileIssue: { path, line (optional), category (Syntax|Style|Policy|Security|Configuration), severity (Blocking|Advisory), message }
- Summary: { counts per category, blockingCount, advisoryCount, durationSeconds }

Special Blocking Case:
- MissingAnalyzerIssue: { path: null, line: null, category: Configuration, severity: Blocking, message: "PSScriptAnalyzer not installed" }

No storage layer or schema required.
