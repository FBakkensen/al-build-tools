# Tasks: 002-add-tests-for – Bootstrap Installer Contract Tests

**Input**: `/specs/002-add-tests-for/` design docs (`plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`)
**Project Type**: Single tooling repo (tests only)
**Scope**: Add contract test coverage for existing `bootstrap/install.sh` & `bootstrap/install.ps1` (no new product code expected unless gaps discovered)

## Generation Notes (Simplified Single-Dev)
- Each contract ID from `contracts/README.md` mapped to at least one test task.
- Some related contracts consolidated into a single test file (noted below) to keep suite lean.
- Failure-path exit code contracts (C-EXIT-CODES) validated inside specific failure tests (no separate file).
- Reporting (C-REPORT) validated inside basic install test (no separate file).
- Git detection + .git metadata (C-GIT, C-GIT-METADATA) combined.
- Preservation + no side effects (C-PRESERVE, C-NO-SIDE-EFFECTS) combined.

## Format
`[ID] [P?] Description (file path)`  – [P] = runnable in parallel (independent files, no ordering dependency).

## Phase 3.1: Setup
- [ ] T001 Create test helper `tests/contract/lib/bootstrap_test_helpers.sh` (hashing, temp dir setup, tool hiding helpers). (New file)

## Phase 3.2: Contract Tests (Write first; they should PASS immediately unless undiscovered gaps)
- [ ] T002 Basic install success + reporting (C-INIT, C-REPORT) in `tests/contract/test_bootstrap_install_basic.sh`
- [ ] T003 Idempotent re-run hashing (C-IDEMP) in `tests/contract/test_bootstrap_install_idempotent.sh` (depends on T002; same destination logic – not parallel)
- [ ] T004 [P] Git vs non-git warning & metadata preservation (C-GIT, C-GIT-METADATA) in `tests/contract/test_bootstrap_install_git_context.sh`
- [ ] T005 [P] Custom destination creation (C-CUSTOM-DEST) in `tests/contract/test_bootstrap_install_custom_dest.sh`
- [ ] T006 [P] Fallback extraction when `unzip` absent (C-FALLBACK) in `tests/contract/test_bootstrap_install_fallback_unzip_missing.sh`
- [ ] T007 [P] Hard failure when both unzip & python absent (C-HARD-FAIL, C-EXIT-CODES) in `tests/contract/test_bootstrap_install_fail_no_extract_tools.sh`
- [ ] T008 [P] Preserve unrelated files & no external side effects (C-PRESERVE, C-NO-SIDE-EFFECTS) in `tests/contract/test_bootstrap_install_preserve_and_no_side_effects.sh`
- [ ] T009 [P] Path containing spaces (C-SPACES) in `tests/contract/test_bootstrap_install_spaces_in_path.sh`
- [ ] T010 [P] Read-only destination failure (C-READONLY, C-EXIT-CODES) in `tests/contract/test_bootstrap_install_readonly_failure.sh`
- [ ] T011 [P] PowerShell parity (C-POWERSHELL-PARITY) in `tests/contract/test_bootstrap_install_powershell_parity.ps1` (skip gracefully if `pwsh` missing)

## Phase 3.3: (Optional) Implementation Adjustments
Only created if a contract test uncovers a behavior gap (none expected). Placeholder tasks reserved:
- [ ] T012 [P] (IF NEEDED) Adjust `bootstrap/install.sh` message wording to satisfy test expectation (update test if message acceptable instead).
- [ ] T013 [P] (IF NEEDED) Adjust `bootstrap/install.ps1` parity to mirror shell script after any change in T012.

## Phase 3.4: Polish
- [ ] T014 [P] Update `quickstart.md` executed test list (remove “(Planned)” & ensure file names match).
- [ ] T015 [P] Update `README.md` with brief note referencing new contract bootstrap tests (optional – keep minimal).

## Dependencies
| Task | Depends On | Rationale |
|------|------------|-----------|
| T002 | T001 | Uses helpers |
| T003 | T002 | Needs baseline install logic reference & hashing helper validated |
| T004 | T002 | Basic install patterns reused (independent destination; can still run in parallel once helper ready – marked [P] after T002) |
| T005 | T002 | Verifies variant path after ensuring base works |
| T006 | T002 | Requires confirmed normal install before simulating missing unzip |
| T007 | T002 | Same as above for failure path |
| T008 | T002 | Baseline presence needed to compare preservation |
| T009 | T002 | Edge case path after base success |
| T010 | T002 | Failure edge after base logic validated |
| T011 | T002 | Mirrors behaviors validated in shell test |
| T012 | (T002–T011) | Only if a gap found |
| T013 | T012 | Mirrors change in PowerShell |
| T014 | (T002–T011) | Doc updates after tests exist |
| T015 | (T014) | README note after quickstart updated |

## Parallel Execution Guidance
After T002 completes, the following can run concurrently:
```
T004 T005 T006 T007 T008 T009 T010 T011
```
Polish tasks (T014, T015) can run in parallel with each other after their deps.

## Helper Script Outline (`tests/contract/lib/bootstrap_test_helpers.sh`)
Functions: `make_temp_dir`, `hide_tool`, `restore_path`, `calc_dir_hashes`, `assert_contains`, `assert_not_contains`.

## Validation Checklist
- [ ] All contract IDs mapped (C-INIT, C-IDEMP, C-GIT, C-CUSTOM-DEST, C-FALLBACK, C-HARD-FAIL, C-PRESERVE, C-GIT-METADATA, C-REPORT, C-EXIT-CODES, C-POWERSHELL-PARITY, C-NO-SIDE-EFFECTS, C-SPACES, C-READONLY)
- [ ] Exit code failure cases covered (T007, T010)
- [ ] Hash-based idempotence covered (T003)
- [ ] PowerShell parity covered (T011)
- [ ] Edge cases (spaces, readonly) covered (T009, T010)
- [ ] Docs updated (T014, T015)

## Notes
- Keep each test under ~10s; avoid repeated network fetch (cache archive via first run? Accept small duplication initially).
- Skip parity test cleanly if `pwsh` unavailable (exit 0 with SKIP notice).
- Prefer `set -euo pipefail` in each shell test, trap cleanup to remove temp dirs.
