## Tasks (Simplified)

1. Add workflow `.github/workflows/static-analysis.yml` triggering on PR events.
2. Create script `scripts/ci/run-static-analysis.sh` implementing checks.
3. Implement shell script scanning with `shellcheck` (blocking on any SC issue severity error/warn).
4. Implement PowerShell syntax parsing; run `Invoke-ScriptAnalyzer`. Absence of the module must emit a blocking Configuration failure ("PSScriptAnalyzer not installed"). Its rule violations follow normal category blocking rules.
5. Add JSON validation + duplicate key + empty mandatory field detection (Python helper embedded or separate script).
6. Add `al.ruleset.json` policy validation (allowed keys, unique IDs, valid actions).
7. Aggregate and emit GitHub annotations + summary; enforce 60s timeout.
8. Update `CONTRIBUTING.md` with static analysis gate section.
9. Document local usage in `AGENTS.md` if helpful.
10. Manual PR test to confirm failing and passing scenarios.

All tasks sequential; no parallelization needed due to small scope.
