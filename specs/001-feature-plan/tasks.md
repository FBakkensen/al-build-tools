# Tasks: Automated Static Analysis Quality Gate on Pull Requests

**Input**: Design documents in `specs/001-feature-plan/`
**Prerequisites**: `plan.md` (required), plus `research.md`, `data-model.md`, `contracts/README.md`, `quickstart.md`

## Execution Flow (Phase 3 Main)
```
1. Load plan.md (fail if missing)
2. Load optional docs (data-model, contracts, research, quickstart)
3. Generate tasks (setup → tests → core → integration → polish)
4. Mark [P] tasks that touch different files & have no deps
5. Number tasks T001.. sequentially
6. Provide dependency & parallel guidance
7. Output this file; ready for implementation
```

## Legend
- Format: `[ ] T### [P?] Description`
- `[P]` = Task can run in parallel (different files / no ordering dependency)
- No `[P]` = Must run sequentially (same file or depends on previous work)

## Phase 3.1: Setup
- [x] T001 Create `scripts/ci/run-static-analysis.sh` scaffold (shebang, strict mode, arg parsing stub, timer start, emit "UNIMPLEMENTED" then exit 1). File: `scripts/ci/run-static-analysis.sh`.
- [x] T002 [P] Add Python helper for duplicate JSON key detection `scripts/ci/json_dup_key_check.py` (reads file path arg, exits 1 on duplicate key; no other logic yet).
- [x] T003 Add GitHub Actions workflow `.github/workflows/static-analysis.yml` (trigger: pull_request on overlay/**, bootstrap/**; single job runs the bash script; allow failure until tests created).

## Phase 3.2: Contract & Integration Tests (TDD)  (MUST precede Phase 3.3)
Contract = workflow quality gate behaviors defined in `contracts/README.md`.
- [x] T004 [P] Contract test: Missing PSScriptAnalyzer produces blocking Configuration issue. Create `tests/contract/test_missing_psscriptanalyzer.sh` that simulates absence (e.g., run script with env var `FORCE_NO_PSSA=1`) and asserts non‑zero exit & grep message.
- [ ] T005 [P] Contract test: Shell syntax error flagged. Create `tests/contract/test_shell_syntax.sh` (create temp bad script under `overlay/scripts/make/linux/` copy, invoke analysis, expect Blocking Syntax issue & non‑zero exit).
- [ ] T006 [P] Contract test: Duplicate JSON keys in `overlay/al.ruleset.json` clone produce failure. Create `tests/contract/test_json_duplicates.sh` (write temp malformed JSON; run analysis; expect failure category Policy/Configuration).
- [ ] T007 [P] Contract test: Clean repo (no injected defects) succeeds. `tests/contract/test_clean_pass.sh` ensures exit 0 and zero Blocking lines.
- [ ] T008 [P] Integration test: Timeout path. `tests/integration/test_timeout.sh` wraps script with `TIMEOUT_SECONDS=1` and injects artificial sleep (env `INJECT_SLEEP=2`) expecting timeout Blocking issue.

## Phase 3.3: Core Implementation (after tests exist & are failing)
Single file focus (`scripts/ci/run-static-analysis.sh`) → sequential.
- [ ] T009 Implement shell script discovery (target: `overlay/**/*.sh` & `bootstrap/*.sh`) + `shellcheck` invocation; map severities to categories (Syntax/Security/Style) and collect FileIssue structs.
- [ ] T010 Implement PowerShell parsing + `Invoke-ScriptAnalyzer` execution for `overlay/**/*.ps1` & `bootstrap/*.ps1`; emit MissingAnalyzerIssue when analyzer absent or `FORCE_NO_PSSA` set.
- [ ] T011 Implement JSON & ruleset validation: parse all `overlay/**/*.json` + `bootstrap/*.json` (exclude node_modules) using Python helper; add `al.ruleset.json` schema checks (allowed top-level keys, unique rule IDs, valid actions).
- [ ] T012 Implement aggregation: severity/blocking logic, counts, GitHub annotation formatting `::error file=...` plus summary stdout.
- [ ] T013 Implement performance & timeout: honor `TIMEOUT_SECONDS` (default 60); abort with Blocking Configuration issue on overrun; capture duration in Summary.

## Phase 3.4: Integration
- [ ] T014 Wire finalized script in workflow: remove temporary allow-failure, add path filtering (`paths:` overlay/**, bootstrap/**), cache nothing, capture analyzer versions in job summary.

## Phase 3.5: Polish
- [ ] T015 [P] Update `CONTRIBUTING.md` (new section "Static Analysis Quality Gate" with local run instructions & failure categories).
- [ ] T016 [P] Update `README.md` (Add brief note & link to quickstart; show one-line local command `bash scripts/ci/run-static-analysis.sh`).
- [ ] T017 [P] Update `quickstart.md` to include categories/table for issue types & exit behavior.
- [ ] T018 Run all tests & ensure they pass/behave as expected (adjust as needed); final verification commit.

## Dependencies
- T001 before all tests & core tasks (script scaffold needed).
- T002 before T011 (JSON duplicate logic).
- T003 before T014 (workflow refinement) & optional to run tests locally (tests call script directly, not workflow).
- Tests (T004–T008) must exist & fail before implementing core tasks T009–T013.
- Core tasks T009–T013 sequential (same file) and precede T014.
- T014 precedes polish tasks that reference final workflow docs (T015–T017).
- T018 is last (depends on all prior tasks complete).

## Parallel Task Groups
Group A (after T001 + T002 + T003): T004 T005 T006 T007 T008 can run together.
Group B (after T014): T015 T016 T017 can run together.

## Parallel Execution Example
```
# After completing T001-003:
bash tests/contract/test_missing_psscriptanalyzer.sh &
bash tests/contract/test_shell_syntax.sh &
bash tests/contract/test_json_duplicates.sh &
bash tests/contract/test_clean_pass.sh &
bash tests/integration/test_timeout.sh &
wait
```

## Validation Checklist
- [ ] All contract behaviors have tests (missing analyzer, shell syntax, JSON duplicates, success path, timeout)
- [ ] Tests precede implementation (T004–T008 before T009–T013)
- [ ] No two [P] tasks modify same file
- [ ] Core logic tasks sequential for single script
- [ ] Documentation updates captured (CONTRIBUTING, README, quickstart)
- [ ] Final verification task present (T018)

## Notes
- Keep implementation minimal: no external network installs unless `shellcheck` absent (document if added).
- Prefer pure bash + pwsh invocation; avoid introducing additional dependency managers.
- Blocking categories: Syntax, Security, Configuration, Policy, (Style if desired) → determine exit code >0 when any present.

---
Generated for feature `001-feature-plan` on 2025-09-10.## Tasks (Simplified)

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
