# Tasks: Add Automated Tests for install.ps1

**Feature Directory**: D:/repos/al-build-tools/specs/005-add-tests-for
**Input Docs Present**: plan.md, research.md, data-model.md, contracts/README.md, quickstart.md, spec.md
**Primary Target**: `bootstrap/install.ps1`

## Generation Context
Derived from functional requirements FR-001..FR-025, conceptual entities (InstallerSession, DownloadAttempt, GuardRailOutcome), quickstart scenarios, and behavioral contracts. Focus: add black-box Pester tests (contract + integration) validating installer reliability, guard rails, diagnostics, overwrite semantics, temp workspace lifecycle, and cross-platform parity. No production code changes unless required to expose stable diagnostic lines (will be driven by initially failing tests).

## Task Format
`[ID] [P?] Description`
[P] = Eligible to execute in parallel (different files / no ordering dependency).
Sequential tasks omit [P] when they touch same file or depend on prior tasks.

## Phase 3.1: Setup (Foundation)
- [x] T001 Create test helper module `tests/_install/Assert-Install.psm1` with shared assertions (temp path pattern, diagnostic line matchers, hash utilities).
- [x] T002 [P] Add test data directory `tests/_install/data/` with minimal fixture (dummy file) for hash/idempotence utilities.
- [x] T003 Ensure Pester configuration update (if needed) in existing `scripts/run-tests.ps1` to auto-discover new `_install` helpers (skip if already globbing all tests).
- [x] T004 Add documentation traceability stub `specs/005-add-tests-for/traceability.md` mapping FR-001..FR-025 → test file IDs (filled as tests added).

## Phase 3.2: Tests First (TDD) – Contract & Integration (Must fail initially where behavior absent)
Guard rails & early failures first, then success/idempotence, then diagnostics categories, then performance & parity.

### Guard Rail Contract Tests (fail-fast scenarios)
- [ ] T005 Create `tests/contract/Install.GitRepoRequired.Tests.ps1` (FR-023) – run installer in dir without `.git` expect non-zero exit & `[install] guard GitRepoRequired` (will initially fail; implementation currently warns and proceeds).
- [ ] T006 Create `tests/contract/Install.WorkingTreeNotClean.Tests.ps1` (FR-024, FR-015 edge) – simulate dirty repo (add untracked + modified file) expect abort & `[install] guard WorkingTreeNotClean`.
- [ ] T007 Create `tests/contract/Install.PowerShellVersionUnsupported.Tests.ps1` (FR-004) – simulate version check via wrapper (may require implementing guard later; mark pending if version already >=7) expect guarded failure pattern.
- [ ] T008 [P] Create `tests/contract/Install.UnknownParameter.Tests.ps1` (FR-008) – call with `-Nope123` expect rejection & usage guidance.
- [ ] T009 [P] Create `tests/contract/Install.NonCleanAfterPartialFailure.Tests.ps1` (FR-015) – induce simulated partial copy (manually place one overlay file) then run installer expect abort & same clean working tree guidance.

### Success & Idempotence
- [ ] T010 Create `tests/integration/Install.Success.Basic.Tests.ps1` (FR-001, FR-006) – assert success summary line placeholder `[install] success ref=` (will fail until added), expected overlay files present, no extraneous writes.
- [ ] T011 [P] Create `tests/integration/Install.IdempotentOverwrite.Tests.ps1` (FR-002, FR-025) – modify file inside overlay between runs; second run restores hash.
- [ ] T012 [P] Create `tests/integration/Install.NoWritesOnFailure.Tests.ps1` (FR-005, FR-014 precondition) – force download failure (invalid ref) assert no overlay file changes.

### Download Failure Categories & Diagnostics
- [ ] T013 Create `tests/contract/Install.DownloadFailure.NetworkUnavailable.Tests.ps1` (FR-014) – simulate network unreachable (e.g., set URL to reserved RFC1918 unreachable) expect single `[install] download failure` line with `category=NetworkUnavailable`.
- [ ] T014 [P] Create `tests/contract/Install.DownloadFailure.NotFound.Tests.ps1` (FR-014) – bogus ref expect `category=NotFound`.
- [ ] T015 [P] Create `tests/contract/Install.DownloadFailure.CorruptArchive.Tests.ps1` (FR-014) – serve/point to corrupt zip (may need local temp zip creation) expect `category=CorruptArchive`.
- [ ] T016 [P] Create `tests/contract/Install.DownloadFailure.Timeout.Tests.ps1` (FR-014) – simulate timeout via extremely slow endpoint stub or injected delay harness (may start as Pending if infra not ready) expect `category=Timeout`.
- [ ] T017 Add `tests/contract/Install.Diagnostics.Stability.Tests.ps1` (FR-009) – assert regex patterns for guard lines, success line, download failure line all anchored.^

### Temp Workspace & Ephemeral Behavior
- [ ] T018 Create `tests/integration/Install.TempWorkspaceLifecycle.Tests.ps1` (FR-019, FR-001) – capture temp path from added `[install] temp` line (test will initially force addition) assert removed post-run.
- [ ] T019 [P] Create `tests/integration/Install.PermissionDenied.Tests.ps1` (FR-020) – create read-only target file causing copy failure expect permission diagnostic & non-zero exit.

### Performance & Isolation
- [ ] T020 Create `tests/integration/Install.PerformanceBudget.Tests.ps1` (FR-010) – measure duration; warn >25s, fail ≥30s.
- [ ] T021 [P] Create `tests/integration/Install.EnvironmentIsolation.Tests.ps1` (FR-011) – run two sequential installs in fresh clones ensuring no cross contamination.

### Cross-Platform Parity (Structure Assertions)
- [ ] T022 Create `tests/integration/Install.Parity.Structure.Tests.ps1` (FR-016, FR-017, FR-018, FR-022) – assert consistent step numbering & messages subset independent of OS (path regex differences allowed).

### Safety / Security Boundaries
- [ ] T023 Create `tests/contract/Install.RestrictedWrites.Tests.ps1` (FR-007) – verify no writes outside overlay path by snapshotting root before & after.

## Phase 3.3: Core Adjustments (Implementation to Satisfy Failing Tests)
(Execute only after all above tests committed & initially failing where behavior absent.)
- [ ] T024 Add guard logic to `bootstrap/install.ps1` for git repo requirement (abort with `[install] guard GitRepoRequired` & exit code 10).
- [ ] T025 Add working tree cleanliness check (abort with `[install] guard WorkingTreeNotClean`).
- [ ] T026 Add unknown parameter validation (abort with usage, exit 10) – may wrap param binder or custom validation.
- [ ] T027 Add PowerShell version guard (if <7.0 warn/fail pattern already satisfied else forced test skip logic) unify with guard prefix.
- [ ] T028 Emit standardized success summary line `[install] success ref=<ref> overlay=<destFull> duration=<secs>`.
- [ ] T029 Emit `[install] temp <path>` line on creation of temp workspace.
- [ ] T030 Implement structured download failure classification & single-line diagnostic w/ categories & exit codes (20 series) – includes mapping failures to {NetworkUnavailable, NotFound, CorruptArchive, Timeout, Unknown}.
- [ ] T031 Ensure temp workspace always removed before exit (existing finally; expand logging) & no overlay copy occurs before verified extraction.
- [ ] T032 Add permission failure detection (wrap copy with try/catch to map to exit 30 with diagnostic `[install] guard PermissionDenied`).
- [ ] T033 Implement restricted write safety verification (guard path scope to overlay only) – fail if copy would escape dest root.
- [ ] T034 Add elapsed time measurement & output (used by performance test) – does not enforce threshold internally (tests assert).
- [ ] T035 Normalize step numbering / messages for parity (stable sequence names).

## Phase 3.4: Integration / Refinement
- [ ] T036 Refactor duplicated assertion helpers into `tests/_install/Assert-Install.psm1` (if drift emerged during implementation tasks).
- [ ] T037 Update `contracts/README.md` exit code table if final exit codes differ; ensure tests updated accordingly (FR-012, FR-013 alignment).
- [ ] T038 Update `traceability.md` with final mapping FR → Test File.

## Phase 3.5: Polish
- [ ] T039 [P] Add inline documentation comments in `bootstrap/install.ps1` for new guard sections referencing FR IDs (limited; avoid noise).
- [ ] T040 [P] Add contributor guide snippet to `README.md` summarizing installer test contract (FR-012).
- [ ] T041 [P] Optimize any slow test setup (cache clone for repeated parity checks without altering overwrite semantics).
- [ ] T042 Final consistency pass: run entire test suite locally (both categories). Capture runtime metrics.

## Dependencies
- T001 before any test using shared helpers (others can scaffold pending if helper absent but recommended first).
- Guard tests (T005-T009) precede related implementation (T024-T027, T030, T032).
- Success/idempotence tests (T010-T012) precede success summary / classification (T028-T031, T034, T035).
- Diagnostic category tests (T013-T017) precede download failure classification (T030).
- Temp / permission tests (T018-T019) precede T029, T031, T032.
- Performance & isolation (T020-T021) rely on success path (T028, T034).
- Parity test (T022) after success + classification established (T028-T031, T034, T035).
- Restricted write test (T023) precedes safety implementation T033.
- Core adjustments (T024-T035) unlock integration/refinement (T036-T038) then polish (T039-T042).

## Parallel Execution Examples
```
# Example 1: Run independent early guard tests in parallel (after T001):
Task: T008 Install.UnknownParameter.Tests.ps1
Task: T009 Install.NonCleanAfterPartialFailure.Tests.ps1

# Example 2: Run idempotence & no-writes failure tests together:
Task: T011 Install.IdempotentOverwrite.Tests.ps1
Task: T012 Install.NoWritesOnFailure.Tests.ps1

# Example 3: Download failure category tests (network infra permitting):
Task: T014 NotFound
Task: T015 CorruptArchive
Task: T016 Timeout

# Example 4: Polish parallel docs & optimization:
Task: T039 Inline docs
Task: T040 README snippet
Task: T041 Optimize slow setup
```

## Validation Checklist
- [ ] All FR-001..FR-025 mapped to at least one test or implementation task.
- [ ] All test tasks precede implementation tasks modifying installer.
- [ ] [P] only on tasks writing distinct files / no ordering conflicts.
- [ ] Traceability doc stub (T004) ensures maintenance clarity.
- [ ] Parity & performance explicitly covered (T020, T022).

## Notes
Some failure mode simulations (NetworkUnavailable, Timeout, CorruptArchive) may require controlled harness; initial tests can be marked Pending within files until harness utilities added, but tasks remain to enforce visibility.

