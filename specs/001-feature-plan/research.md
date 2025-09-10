## Research: Static Analysis Quality Gate

### Goal
Lightweight, fast static checks on PRs affecting distributed tooling (`overlay/`, `bootstrap/`). Avoid heavy frameworks; leverage existing tools on GitHub Actions Ubuntu runner.

### Decisions
1. Shell script analysis: Use `shellcheck` (preinstalled or install via apt if missing). Blocking severities SC* relevant to syntax/security/style.
   - Rationale: Mature, fast, granular diagnostics.
   - Alternatives: Bash `-n` only (insufficient coverage), custom regex (fragile).
2. PowerShell analysis: Use `pwsh -NoLogo -Command { [System.Management.Automation.PSParser]::Tokenize(...) }` for syntax AND always run `Invoke-ScriptAnalyzer`. The module is REQUIRED; if it is not installed the run records a single blocking Configuration issue "PSScriptAnalyzer not installed" and the gate fails.
   - Rationale: Ensures consistent enforcement parity with shell analysis and prevents silent degradation of security/style checks.
3. JSON validation: Use `jq` for parse + structural checks. Implement duplicate key detection by re-parsing with `jq -S` and comparing raw length? Simpler: Use Python one-liner with `json.load` + custom object_pairs_hook to detect duplicates.
   - Decision: Python approach (available on runner) for duplicate key detection and pointer context.
4. `al.ruleset.json` policy validation: Minimal bash/python script verifying allowed top-level keys and rule uniqueness + action set membership.
5. Workflow trigger: `pull_request` on opened, synchronize, reopened; single job `static-analysis`.
6. Performance guard: Measure elapsed time; if exceeding 60s, fail with explicit timeout message.
7. Diagnostics format: `::error file=path,line=LINE::[Category] message` for GitHub annotations; summary step listing counts per category.

### Alternatives Considered
- Full containerized lint stage: Overkill; increases cold start latency.
- Composite action packaging: Deferred until stability proven.
- Adding parity enforcement now: Out of scope per spec (future phase).

### Open Issues Resolved
No remaining NEEDS CLARIFICATION; scope narrow and tool availability assumed on Actions hosts.

### Risks
1. Missing `shellcheck` would require install (adds a few seconds). Acceptable.
2. Missing `PSScriptAnalyzer` now blocks the gate; risk of unexpected failure on first run if runner image changes or module not preinstalled.
   - Mitigation: Explicit early capability check with clear blocking message and link to CONTRIBUTING section describing installation.
3. Analyzer version drift could introduce new rules causing sudden gate failures.
   - Mitigation: Log analyzer version in summary; if instability observed, pin version via `Install-Module PSScriptAnalyzer -RequiredVersion <x>` in workflow.
4. Performance regression if analyzer rule set grows significantly.
   - Mitigation: Measure elapsed analyzer time; if > N seconds (e.g., 15) emit advisory to consider rule pruning.

### Next Steps
Implement helper script `scripts/ci/run-static-analysis.sh` invoked by workflow; update `CONTRIBUTING.md` with gate description.
