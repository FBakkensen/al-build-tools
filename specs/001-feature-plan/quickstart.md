## Quickstart: Static Analysis Quality Gate

1. Open a PR modifying files under `overlay/` or `bootstrap/`.
2. GitHub Actions runs job `static-analysis` automatically.
3. View Checks tab → see annotations inline (shell, PowerShell, JSON issues).
4. Fix blocking issues (Syntax, Security, Configuration, Policy, Style) until status passes. Advisory issues may remain but are reported.
5. Push changes; workflow re-runs.

PowerShell analyzer behavior:
- `PSScriptAnalyzer` is REQUIRED. Its findings are enforced (can block) using the same category rules.
- If it is NOT installed the run records a blocking Configuration issue: "PSScriptAnalyzer not installed" and the quality gate fails.

Local replication (Linux):
```
bash scripts/ci/run-static-analysis.sh
```
(Script will exit non-zero on blocking findings.)

## Issue categories and exit behavior

- Syntax — Blocking. Examples: bash parse errors, PSScriptAnalyzer errors.
- Security — Blocking. Examples: PowerShell warnings (PSScriptAnalyzer). Note: shellcheck warnings are treated as advisory Style.
- Configuration — Blocking. Examples: invalid JSON, duplicate JSON keys, missing PSScriptAnalyzer, pwsh not installed, TIMEOUT exceeded.
- Policy — Blocking. Examples: overlay/al.ruleset.json schema issues (invalid keys, duplicate rule ids, invalid actions).
- Style — Advisory only; does not fail the gate.

Exit semantics:
- The script exits with code 1 if any blocking issues are present; otherwise exits 0.
- Missing PSScriptAnalyzer or an exceeded TIMEOUT is treated as a blocking Configuration issue.
