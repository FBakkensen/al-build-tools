## Contracts
No external service/API contracts. The "contract" is the GitHub workflow status context:

- Context name: `static-analysis`
- Conclusion: `success` (no blocking) or `failure` (≥1 blocking issue or timeout/tool missing)
- Output summary: counts per category.
- Analyzer Requirement: `PSScriptAnalyzer` must be installed. Its diagnostics integrate into pass/fail. If missing, emit blocking Configuration failure: "PSScriptAnalyzer not installed".
