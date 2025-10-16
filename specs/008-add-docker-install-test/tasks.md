# Tasks: Docker-Based Install Script Test

Generated: 2025-10-16
Feature Directory: `specs/008-add-docker-install-test`

## Overview
Phased implementation plan to deliver an independently testable containerized validation of `bootstrap/install.ps1`. User stories prioritized (P1→P3) and each phase yields a verifiable increment. Tests here are implicit (exit code + artifact presence); no Pester suite in MVP per plan/spec.

## Phase 1 – Setup (Local-First)
Establish local harness scaffolding only (no CI workflow yet) to enable iterative local development before automation.

- [x] T001 Create output directory placeholder `out/test-install/.gitkeep`
- [x] T002 Create script scaffold for harness in `scripts/ci/test-bootstrap-install.ps1`
- [x] T003 Ensure JSON schema file present `specs/008-add-docker-install-test/contracts/installer-test-summary.schema.json`
- [x] T004 [P] Add helper PowerShell function section headers inside `scripts/ci/test-bootstrap-install.ps1` (Parse-Release, Invoke-ContainerRun, Write-Summary)
- [x] T005 Write schema validation note in `scripts/ci/test-bootstrap-install.ps1` comments referencing `contracts/installer-test-summary.schema.json`
- [x] T005a Add G14 schema alignment explanatory note to spec (no schema expansion)
- [x] T006 Add `.gitignore` rule (if absent) for `out/test-install/` in root `.gitignore`

## Phase 2 – Foundational
Core mechanics & resilience primitives (container provisioning, release tag resolution, logging, cleanup). NOTE: Download + checksum tasks (T009–T011b) were implemented initially but later removed via refactor; installer now exclusively owns overlay acquisition & integrity. Their historical completion remains marked for traceability but harness no longer executes that logic.

- [x] T007 Implement release tag resolution (env `ALBT_TEST_RELEASE_TAG` else latest) in `scripts/ci/test-bootstrap-install.ps1`
- [x] T008 [P] Implement latest release lookup via GitHub API (unauth or token) in `scripts/ci/test-bootstrap-install.ps1`
- [x] T009 (Deprecated) Harness artifact download (removed; handled by bootstrap installer)
 - [x] T010 (Deprecated) Retry logic for harness download (removed)
 - [x] T011 (Deprecated) Harness checksum logging (removed)
 - [x] T011a (Deprecated) gh digest retrieval (removed)
 - [x] T011b (Deprecated) Integrity verification inside harness (removed)
 - [x] T012 Implement container image resolution (env `ALBT_TEST_IMAGE` fallback `mcr.microsoft.com/windows/servercore:ltsc2022`)
 - [x] T013 Capture image pull & container create timing; add `imagePullSeconds`,`containerCreateSeconds` to summary
 - [x] T014 [P] Early failure classification for image pull vs container create populating `errorCategory`
 - [x] T015 Implement transcript start/stop using `Start-Transcript` writing to `out/test-install/install.transcript.txt`
 - [x] T016 [P] Implement structured error trap and final exit code propagation in `scripts/ci/test-bootstrap-install.ps1`
 - [x] T017 Implement structured summary object creation and write JSON `out/test-install/summary.json`
 - [x] T017a [P] Add optional `runId`, `startedAtUtc`, `endedAtUtc` + transcript header line
 - [x] T017b [P] (G18) Optionally populate `logs` object (transcript path + failure additional logs)
 - [x] T018 [P] Implement environment flag `ALBT_TEST_KEEP_CONTAINER` to skip auto-remove for debugging
 - [x] T019 Implement container cleanup logic (remove container on success/failure unless keep flag)
 - [x] T019a [P] Add try/finally wrapper + random container name + idempotent force removal function
 - [x] T020 Export `ALBT_AUTO_INSTALL=1` for container run to enable non-interactive PowerShell 7 installation in `scripts/ci/test-bootstrap-install.ps1`
 - [x] T021 Validate PowerShell 7 presence inside container (record version in summary) after potential auto-install
 - [x] T022 [P] Add strict mode + error preference to `scripts/ci/test-bootstrap-install.ps1`
 - [x] T022a [P] Implement deterministic `errorCategory`→exit code mapping (guard & missing-tool precedence)
 - [x] T023 Add verbose logging controlled by host `$VerbosePreference` / env `VERBOSE`
 - [x] T023a Apply standardized 30s network timeout to release/digest/download requests

## Phase 3 – User Story 1 (P1) Validate Installer In Clean Container (Local)
Deliver minimal successful end-to-end install path locally before introducing CI automation.

Story Goal: Execute the **actual** `bootstrap/install.ps1` inside a clean Windows container and confirm success with artifacts.
Independent Test Criteria: Local run; expect exit code 0, presence of transcript & summary with `success=true`.

- [x] T024 [US1] Add container run command building from base image executing bootstrap install sequence in `scripts/ci/test-bootstrap-install.ps1` (invokes actual bootstrap/install.ps1)
- [x] T025 [P] [US1] Inject logic to copy `bootstrap/` directory into container via `docker cp` (not overlay.zip)
- [x] T026 [US1] Implement inside-container invocation command string in `scripts/ci/test-bootstrap-install.ps1` (runs installer with appropriate parameters)
- [x] T027 [P] [US1] Capture container process exit code and map to harness exit
- [x] T028 [US1] Populate `out/test-install/summary.json` with success fields (`exitCode`,`success`,`durationSeconds`) and reference artifacts (`install.transcript.txt`, `summary.json`, failure-only `provision.log`)
- [x] T029 [P] [US1] Validate summary JSON conforms to schema fields subset (basic key presence) before script exit
- [x] T030 [P] [US1] Document local run instructions appendix in `quickstart.md` referencing harness script (update existing section)

## Phase 4 – User Story 2 (P2) Surface Actionable Failures (Local Diagnostics)
Augment harness to produce rich diagnostics for failing runs (still local-focused; CI hooks deferred to later phase).

Story Goal: Provide concise failure summaries and comprehensive logs/artifacts when install fails. (Refactor note: Timed phases no longer include download phase since harness delegates overlay download to installer.)
Independent Test Criteria: Simulate failure (e.g., set bad release tag) and confirm non-zero exit code plus summary `errorSummary` and artifact presence.

- [x] T031 [US2] Add failure classification (network vs install) populating `errorSummary` in `scripts/ci/test-bootstrap-install.ps1`
- [x] T032 [P] [US2] Add timed sections with start/stop timestamps for phases (release-resolution, container-provisioning) appended to summary (download phase removed in refactor)
- [x] T033 [US2] Add container stdout/stderr tail extraction on failure appended to transcript file
- [x] T034 [P] [US2] Add retry (1 attempt) for release metadata fetch before failing hard
- [x] T035 [US2] Persist container provisioning log segment into `out/test-install/provision.log`
- [x] T036 [P] [US2] Include hashed image ID and container ID in summary JSON
- [x] T037 [P] [US2] Add guard to truncate overly large transcript (>5MB) with note

## Phase 5 – User Story 3 (P3) Reproduce Test Locally
Enable frictionless local execution mirroring future CI behavior.

Story Goal: Single documented command replicates CI results on maintainer machine.
Independent Test Criteria: Local execution yields same artifacts & exit semantics as CI.

- [x] T038 [US3] Add usage/help output (`-Help` or `-?`) to `scripts/ci/test-bootstrap-install.ps1`
- [x] T039 [P] [US3] Add detection of missing Docker engine with clear message and exit code 6 (MissingTool)
- [x] T040 [US3] Add quickstart reproduction snippet update with env variable examples in `specs/008-add-docker-install-test/quickstart.md`
- [x] T042 [P] [US3] Add validation step printing resolved configuration block (image, release tag) at start
- [x] T043 [US3] Add safety check preventing execution on non-Windows host (exit code 6) if attempted
 - [x] T043a [US3] Document integrity verification (gh digest + `ALBT_TEST_EXPECTED_SHA256`) in `quickstart.md`

## Phase 6 – CI Integration
Introduce GitHub Actions workflow only after local harness is fully validated and reproducible. (No user story label – automation layer.)

- [ ] T044 Create GitHub Actions workflow scaffold `.github/workflows/test-bootstrap-install.yml`
- [ ] T045 Add workflow job step to upload `out/test-install` as artifact `installer-test-logs`
- [ ] T046 Enhance workflow to echo condensed failure summary to job log on failure
- [ ] T047 Ensure workflow uses identical command line as documented (no hidden flags)

## Final Phase – Polish & Cross-Cutting
Refinements, consistency, maintainability improvements post-story & CI integration completion.

- [ ] T048 Add PSScriptAnalyzer compliance pass for `scripts/ci/test-bootstrap-install.ps1`
- [ ] T049 [P] Add comment headers + synopsis, parameter docs in script
- [ ] T050 Add CHANGELOG entry referencing added installer test harness
- [ ] T051 [P] Optimize download by honoring `GITHUB_TOKEN` for higher rate limits
- [ ] T052 Add failure example section to `specs/008-add-docker-install-test/quickstart.md` describing diagnostic interpretation
- [ ] T053 [P] Add schema version field in summary JSON (future-proofing) if backward-compatible
- [ ] T054 Final review: ensure no overlay/ files modified, only harness + workflow

## Dependency Graph (User Stories & Phases)
US1 → US2 (adds diagnostics) → US3 (local parity) → CI Integration (automates) → Polish

## Parallel Execution Opportunities
Examples:
- During Phase 2: T009 (latest release lookup) parallel with T011 (checksum logging), T014 (error trap), T016 (keep flag), T019 (strict mode)
- Phase 3: T022 (docker cp) parallel with T024 (exit capture) and T028 (doc update)
- Phase 4: T030 (timed sections) parallel with T032 (retry) and T034 (IDs)
- Phase 5: T038 (Docker detection) parallel with T040 (doc update) and T042 (config print)

## Implementation Strategy
1. MVP (Complete after Phase 3): Provides baseline automated installer validation (US1) – sufficient to block releases on installer failure.
2. Enhanced Diagnostics (Phase 4): Improves triage speed without altering success path.
3. Local Parity (Phase 5): Reduces iteration friction for maintainers.
4. Polish: Documentation, analyzers, minor resilience improvements.

## Task Validation
All tasks follow required checklist format: `- [ ] T### [P?] [US#?] Description with file path`.
Story phases (3–5) include `[US#]` labels; other phases omit them per rules. All tasks include concrete file paths.

## Task Counts
 - Total Tasks: 61
 - Phase 1 (Setup Local): 7
 - Phase 2 (Foundational): 24
 - Phase 3 (US1 Local Validation): 7
 - Phase 4 (US2 Diagnostics): 7
 - Phase 5 (US3 Local Repro): 6
 - Phase 6 (CI Integration): 4
 - Final Polish: 7

## MVP Scope Recommendation
Deliver through T029 (inclusive) to meet primary success criterion of local installer validation (US1) before adding diagnostics or CI.

## Independent Test Criteria Summary
- US1: Successful run exit code 0; transcript + summary present; success=true.
- US2: On induced failure, non-zero exit; summary includes errorSummary; artifacts uploaded.
- US3: Local invocation replicates CI artifacts and semantics with documented command.

## Parallelizable Task IDs
Parallel-marked tasks: T004,T008,T011,T011a,T011b,T014,T016,T017a,T019,T019a,T021,T022a,T023a,T024,T026,T028,T029,T031,T033,T035,T037,T038,T040,T042? (CI),T044? (CI),T048,T050,T052

