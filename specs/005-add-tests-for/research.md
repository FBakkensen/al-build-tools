# Research: Test Strategy for install.ps1

## Decisions

### Test Framework & Execution
- Decision: Use existing Pester-based test structure (contract + integration) mirroring current tests under `tests/`.
- Rationale: Maintains repository consistency; no new dependency; aligns with constitutional parity & repeatability.
- Alternatives: Introduce separate bootstrap test harness – rejected (added complexity, violates minimal surface & simplicity tenet).

### Cross-Platform Strategy
- Decision: Reuse existing CI matrix (Windows + Ubuntu) and ensure new tests are OS-agnostic by normalizing path assertions.
- Rationale: Constitution requires parity; simpler than branching logic.
- Alternatives: Separate OS-specific test files – rejected (duplication risk, divergence).

### Temporary Workspace Detection
- Decision: Capture installer transcript; parse logged temp path (require stable prefix `[install] temp` to be added if missing in implementation scope).
- Rationale: Enables asserting creation & cleanup without internal coupling.
- Alternatives: Environment variable injection – rejected (would expand public surface & encourage implicit config; constitution discourages hidden knobs).

### Failure Category Assertions (FR-014)
- Decision: Pattern match single-line diagnostic with anchored regex: `^\[install] download failure ref=.+ url=.+ category=(NetworkUnavailable|NotFound|CorruptArchive|Timeout|Unknown) hint=.+$`.
- Rationale: Stable, explicit; resilient to ordering changes in other output.
- Alternatives: Multi-line JSON diagnostic – rejected (increases verbosity, no current need).

### Performance Budget (FR-010)
- Decision: Soft threshold <30s enforced via measuring elapsed time in integration test; test warns (Assert-Verifiable) if >25s and fails if ≥30s.
- Rationale: Early regression signal while allowing minor variance.
- Alternatives: No timing – rejected (requirement explicit); strict <25s fail – rejected (risk of flaky CI on cold network).

### Working Tree Cleanliness Detection
- Decision: Reuse `git status --porcelain=v1` in test harness to introduce modifications/untracked files and assert non-zero exit + guidance phrase.
- Rationale: Black-box: does not rely on implementation internals; replicates user scenario.

### Idempotent Overwrite Verification
- Decision: First run: record file hashes under overlay path. Modify a file inside overlay manually. Second run: assert modified file restored to original content and all hashes realign.
- Rationale: Directly validates ephemeral model (FR-002, FR-025).

### Simulated Partial Failure (FR-015)
- Decision: Induce failure before copy by mocking network (provide invalid ref) then manually create one overlay file; next run must abort due to dirty working tree.
- Rationale: Simulates edge case without altering installer logic.

### Permission / Read-Only Scenario (FR-020)
- Decision: Create destination subdirectory with read-only attribute (Windows: attrib +R; Linux: chmod 500) affecting a file to be overwritten; assert permission diagnostic.
- Rationale: Minimal, portable approach.

## Open Items Resolved
- All functional requirements mapped to test strategies above; no remaining NEEDS CLARIFICATION.

## Alternatives Considered (Summary)
- Custom test harness: rejected (complexity).
- JSON structured logs: deferred until demonstrable need.
- Caching downloads: out-of-scope per spec (FR-025 ensures overwrite each run).

## Impact on Constitution
- Parity maintained (tests run both OSes).
- Repeatability enforced (tests isolate temp dirs, restore state via fresh git clone for each run).
- Transparent contracts: New diagnostic patterns codified.

## Risks
- Performance flakiness due to network variability – mitigated with warn/fail thresholds.
- Diagnostic wording drift – mitigated by specifying anchored regex patterns (explicit contract).

## Next Steps
- Phase 1: Formalize data model (conceptual entities: InstallerSession, GuardRailOutcome, DownloadAttempt) purely for test traceability.
- Ensure plan.md includes Progress Tracking updates after Phase 0 completion.
