# Tasks: Manual Release Workflow (Feature 006)

Input: Design documents under `specs/006-manual-release-workflow/`
Prerequisites: `plan.md` (required), `research.md`, `data-model.md`, `contracts/acceptance-criteria.md`, `contracts/success-metrics.md`, `quickstart.md`

Goal: Implement a manual (`workflow_dispatch`) release pipeline producing an overlay‑only zip artifact with hash manifest, diff summary, metadata block, and supporting tests & docs.

---
Execution Flow (main)
```
1. Scaffold workflow file & inputs
2. Add contract & integration tests (red state)
3. Add entity helper scripts (models) powering workflow steps
4. Implement validation & packaging steps in workflow (sequential)
5. Implement release notes + dry-run logic
6. Add performance / integrity guards
7. Update documentation & finalize polish
8. All tests green; dry-run & real-run verification
```

Format: `[ID] [P?] Description`
 - [P] indicates parallel-safe (different files / no ordering dependency)
 - Omit [P] when tasks touch same file or depend on earlier step

Path Conventions: Helper scripts live under `scripts/release/` (internal, NOT copied to overlay). Workflow: `.github/workflows/release-overlay.yml`. Tests under existing `tests/` structure.

---
Phase 3.1: Setup
- [x] T001 Create initial workflow skeleton `.github/workflows/release-overlay.yml` with `workflow_dispatch` inputs (`version`, `summary`, `dry_run`) and minimal job scaffold (no steps yet).
- [x] T002 Add repository safety comment block & required permissions (contents: write) to `.github/workflows/release-overlay.yml`.

Phase 3.2: Tests First (TDD)  (All must exist & fail before implementation)
- [x] T003 [P] Contract test for acceptance criteria in `tests/contract/ReleaseWorkflow.AcceptanceCriteria.Tests.ps1` validating presence of planned steps / required inputs (stub assertions initially failing).
- [x] T004 [P] Contract test for success metrics in `tests/contract/ReleaseWorkflow.SuccessMetrics.Tests.ps1` asserting placeholders for duration/hash metrics collection.
- [x] T005 [P] Integration test: dry run produces no tag/release, artifacts exist in `tests/integration/release/DryRun.Tests.ps1`.
- [x] T006 [P] Integration test: real run creates tag + release + asset in `tests/integration/release/PublishBasic.Tests.ps1`.
- [x] T007 [P] Integration test: hash manifest completeness & root hash reproducibility in `tests/integration/release/HashManifest.Tests.ps1`.
- [x] T008 [P] Integration test: overlay isolation (no extraneous files) in `tests/integration/release/OverlayIsolation.Tests.ps1`.
- [x] T009 [P] Integration test: non-monotonic version abort in `tests/integration/release/VersionMonotonicity.Tests.ps1`.
- [x] T010 [P] Integration test: tag collision abort in `tests/integration/release/TagCollision.Tests.ps1`.
- [x] T011 [P] Integration test: dirty overlay abort in `tests/integration/release/DirtyOverlay.Tests.ps1`.
- [x] T012 [P] Integration test: maintainer summary inclusion in `tests/integration/release/SummaryInNotes.Tests.ps1`.
- [x] T013 [P] Integration test: diff summary sections correct in `tests/integration/release/DiffSummary.Tests.ps1`.
- [x] T014 [P] Integration test: metadata JSON block presence & schema in `tests/integration/release/MetadataBlock.Tests.ps1`.
- [x] T015 [P] Integration test: immutability (re-run same version fails) in `tests/integration/release/Immutability.Tests.ps1`.
- [x] T016 [P] Integration test: performance (duration ≤ target) in `tests/integration/release/PerformanceBudget.Tests.ps1`.
- [x] T017 [P] Integration test: rollback availability (prior release still downloadable) in `tests/integration/release/RollbackAvailability.Tests.ps1`.
- [x] T018 [P] Integration test: failure transparency single-line error in `tests/integration/release/FailureTransparency.Tests.ps1`.

Phase 3.3: Core Entity Helper Scripts (Models)  (Parallel; distinct files)
- [x] T019 [P] Implement Version + ReleaseTag helpers in `scripts/release/version.ps1` (parse, compare semver, tag existence check).
- [x] T020 [P] Implement OverlayPayload scanner in `scripts/release/overlay.ps1` (deterministic file list, counts, sizes).
- [x] T021 [P] Implement HashManifest generator in `scripts/release/hash-manifest.ps1` (per-file SHA-256 + root hash computation).
- [x] T022 [P] Implement DiffSummary generator in `scripts/release/diff-summary.ps1` (Added/Modified/Removed classification; initial release handling).
- [x] T023 [P] Implement ReleaseArtifact packager in `scripts/release/release-artifact.ps1` (zip creation without wrapper, embed manifest).
- [x] T024 [P] Implement ReleaseNotes composer in `scripts/release/release-notes.ps1` (summary, diff, metadata JSON block template).
- [x] T025 [P] Implement ValidationGate orchestrator in `scripts/release/validation-gates.ps1` (clean overlay, uniqueness, monotonicity, isolation, dry-run safety logic stubs returning structured diagnostics).

Phase 3.4: Workflow Implementation (Sequential – same YAML file)
- [x] T026 Add checkout + git fetch depth step in `.github/workflows/release-overlay.yml`.
- [x] T027 Add step invoking `version.ps1` for input normalization & monotonicity validation (fail fast) in workflow YAML.
- [x] T028 Add step invoking `overlay.ps1` to enumerate files and expose counts as outputs.
- [x] T029 Add step invoking `hash-manifest.ps1` to produce `manifest.sha256.txt` (upload as artifact in dry run path too).
- [x] T030 Add step invoking `diff-summary.ps1` to produce structured diff output file for later notes composition.
- [x] T031 Add conditional dry-run block: upload manifest + diff + metadata preview; set outputs; skip remaining steps if true.
- [x] T032 Add tag creation step (annotated) using version helper (abort if collision) in workflow YAML.
- [x] T033 Add artifact packaging step invoking `release-artifact.ps1` and uploading resulting zip as release asset draft placeholder.
- [x] T034 Add release notes composition & release publish step invoking `release-notes.ps1` (inject maintainer summary when provided) and finalize published release.
- [x] T035 Add post-publish verification step (re-fetch release, validate single asset & metadata JSON block present) in workflow YAML.

Phase 3.5: Integration / Guards
- [x] T036 Add failure transparency wrapper ensuring each gate emits single-line `ERROR:` message on abort (shared function or inline) in `scripts/release/validation-gates.ps1`.
- [x] T037 Add performance timing capture & log (start/end, compute duration) integrated into workflow (modify `.github/workflows/release-overlay.yml`).
- [x] T038 Add root hash reproduction verification step (regen & compare) in workflow YAML.
- [x] T039 Add isolation guard verifying no non-overlay file included (audit packaged zip list) in workflow YAML.

Phase 3.6: Polish
- [ ] T040 [P] Unit tests for Version & semver comparisons in `tests/unit/release/Version.Tests.ps1`.
- [ ] T041 [P] Unit tests for hash-manifest root hash determinism in `tests/unit/release/HashManifest.Tests.ps1`.
- [ ] T042 [P] Unit tests for diff summary classification in `tests/unit/release/DiffSummary.Tests.ps1`.
- [ ] T043 Add README section referencing manual release workflow & verification (modify `README.md`).
- [ ] T044 Add release process link from Quickstart to README (modify `specs/006-manual-release-workflow/quickstart.md`).
- [ ] T045 Refine error messages & diagnostics (update helper scripts) for clarity & consistency.
- [ ] T046 Final dry run example capture & attach logs to PR (manual execution & commit log update `CHANGELOG.md` if needed).
- [ ] T047 Remove any obsolete TODO comments and ensure scripts avoid network calls beyond GitHub API.
- [ ] T048 Update traceability table (append to this file or spec) confirming all FRs mapped to implemented tasks.

Dependencies
```
T001 → T002..T018 (tests rely on workflow skeleton existing)
Tests (T003–T018) must exist & fail before T019+ (core implementation)
T019–T025 (helpers) before T026–T035 (workflow uses helpers)
T026–T035 before T036–T039 (guards depend on base workflow)
All core (≤T039) before polish (T040–T048)
Shared YAML file tasks (T026–T035, T037, T038, T039) run sequentially (no [P])
Parallel-suitable groups: {T003–T018}, {T019–T025}, {T040–T042}
```

Parallel Execution Example
```
# Example: launch initial integration tests concurrently (after T001):
Run-Task T005; Run-Task T006; Run-Task T007; Run-Task T008; Run-Task T009 \
  ; Run-Task T010; Run-Task T011; Run-Task T012; Run-Task T013; Run-Task T014 \
  ; Run-Task T015; Run-Task T016; Run-Task T017; Run-Task T018

# Example: build core helper scripts in parallel (after tests red):
Run-Task T019; Run-Task T020; Run-Task T021; Run-Task T022; Run-Task T023; Run-Task T024; Run-Task T025

# Example: unit test polish tasks:
Run-Task T040; Run-Task T041; Run-Task T042
```

Traceability (Functional Requirement → Tasks)
| FR | Coverage Tasks |
|----|----------------|
| FR-01 (Manual trigger) | T001, T026 |
| FR-02 (Overlay-only artifact) | T023, T033, T039 |
| FR-03 (Clean overlay state) | T025, T027, T011 test |
| FR-04 (Version monotonicity + uniqueness) | T019, T027, T009, T010 tests |
| FR-05 (Deterministic version tagging) | T032, T033 |
| FR-06 (Hash manifest) | T021, T029, T007 test, T038 verify |
| FR-07 (Diff summary) | T022, T030, T013 test |
| FR-08 (Maintainer summary) | T024, T034, T012 test |
| FR-09 (Dry run mode) | T031, T005 test |
| FR-10 (Abort overwrite) | T027/T032 logic, T015 test |
| FR-11 (Immutability) | T015 test, T032 tag step |
| FR-12 (Metadata block) | T024, T034, T014 test |
| FR-13 (Consumer docs) | T043, T044 |
| FR-14 (No external deps) | T025 gates, T045 review |
| FR-15 (Performance) | T037 timing, T016 test |

Validation Checklist
- [ ] All contract files have tests (T003, T004)
- [ ] All entities mapped to helper scripts (T019–T025)
- [ ] Tests precede implementation (T003–T018 before T019+)
- [ ] Parallel tasks touch distinct files only
- [ ] Each task specifies explicit file path(s)
- [ ] Root hash determinism validated (T038, T041)
- [ ] Diff classification validated (T042, T013)

Completion Criteria
- Dry run (T031) outputs manifest + diff + metadata; no tag
- Real run publishes release tagged & asset present; tests green
- All FRs mapped; performance test passes; docs updated

Notes
- Helper scripts intentionally internal (not under `overlay/`) to preserve minimal public surface.
- Avoid adding network calls in helper scripts (FR-14 compliance).
- If future signing added, new tasks will extend beyond T048 with clear gating.

