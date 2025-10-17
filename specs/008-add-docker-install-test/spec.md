# Feature Specification: Docker-Based Install Script Test

**Feature Branch**: `008-add-docker-install-test`
**Created**: 2025-10-16
**Status**: Draft
**Input**: User description: "create a test for install.ps1 it should be a docker based test, that spins up a windows docker container, with the absolut minimal setup to run install.ps1 and make all installs from there and give feedback on success or errors"

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - Validate Installer In Clean Container (Priority: P1)

Release maintainers can trigger an automated check that provisions a clean Windows Docker container, runs the bootstrap install script end-to-end, and confirms the overlay installs without manual steps. Harness delegates all overlay acquisition & integrity verification to the installer itself (no duplicated download logic).

**Why this priority**: Proves that the public installer still works for new consumers, preventing shipping a broken release.

**Independent Test**: Execute the containerized test workflow against the latest release artifact and confirm it reports a green result without any human intervention.

**Acceptance Scenarios**:

1. **Given** a host with Windows Docker support and network access, **When** the installer test runs against the latest release, **Then** the container completes the install with exit code 0 and the job reports success.
2. **Given** a clean container with no prior tool cache, **When** the test runs, **Then** all required dependencies are downloaded during the run and the install finishes successfully.

---

### User Story 2 - Surface Actionable Failures (Priority: P2)

Release maintainers receive clear failure feedback (exit code, transcript, key logs) whenever the installer test cannot complete.

**Why this priority**: Speeds up root cause discovery so a broken installer never ships unnoticed.

**Independent Test**: Introduce a controlled failure (such as blocking network access) and verify the test job captures diagnostics and flags the run as failed with clear messaging.

**Acceptance Scenarios**:

1. **Given** the installer exits with a non-zero status inside the container, **When** the test concludes, **Then** the job marks the run as failed, publishes captured logs, and records the failing step in the report.

---

### User Story 3 - Reproduce Test Locally (Priority: P3)

Maintainers can run the same containerized installer check on a local Windows machine before opening a release PR.

**Why this priority**: Enables faster iteration by letting maintainers debug installer issues without waiting for CI.

**Independent Test**: Follow the documented local command to run the containerized test on a Windows host and confirm it mirrors CI behavior and reporting.

**Acceptance Scenarios**:

1. **Given** a maintainer with Docker for Windows enabled, **When** they execute the documented local command, **Then** the container test runs to completion and reports results consistent with CI outcomes.

---

### Edge Cases

- Installer release asset temporarily unavailable or download exceeds timeout.
- Docker host lacks permission to pull the required Windows base image.
- Re-running the test should not reuse stale symbol or tool caches from prior runs.
- Network hiccups mid-run should surface as failures with clear log context.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The test harness MUST provision an ephemeral Windows Docker container with only the prerequisites needed to execute `bootstrap/install.ps1`.
- **FR-002**: The harness MUST execute the **actual** `bootstrap/install.ps1` script exactly as a new consumer would, allowing the installer to perform overlay download, integrity checks, and extraction (harness MUST NOT replicate these steps).
- **FR-003**: The harness MUST capture: (a) exit code, (b) console transcript file `install.transcript.txt`, and (c) installer summary file `summary.json` (plus `provision.log` only when a failure occurs), marking the test as failed when the installer exits non-zero.
- **FR-004**: The harness MUST publish those captured artifacts (`install.transcript.txt`, `summary.json`, and on failure `provision.log`) as part of the test result for both success and failure cases.
- **FR-005**: The harness MUST clean up containers and temporary assets after each run to avoid cross-test contamination and excessive resource use.
- **FR-006**: The harness MUST ensure PowerShell 7.2+ is available (validate OR install). If the base image lacks it, the harness MUST enable non-interactive installation by exporting `ALBT_AUTO_INSTALL=1` before invoking `bootstrap/install.ps1` so the existing installer logic performs the upgrade without user prompts.
- **FR-007**: The harness SHOULD enrich the summary (when data is obtainable) with early lifecycle timing metrics (`imagePullSeconds`, `containerCreateSeconds`). Absence of these optional fields MUST NOT cause the test to fail.
- **FR-008**: (Refactored) Integrity verification of the overlay asset is the responsibility of `bootstrap/install.ps1`; the harness MUST NOT perform independent checksum or digest validation to avoid divergence. The harness MAY still surface installer failures related to integrity via exit code and transcript.

### Key Entities *(include if feature involves data)*

- **Test Container Run**: Represents a single execution of the installer inside an isolated Windows Docker container; key attributes include image identifier, start/end timestamps, and exit status.
- **Installer Execution Report**: Aggregates transcripts, captured logs, and pass/fail outcome produced by a container run; shared with maintainers via CI artifacts or local output.

## Assumptions

- Maintainers have access to a Windows host capable of running Windows-based Docker containers (CI agent or local machine).
- The bootstrap installer release asset remains reachable over the network during test execution.
- Docker and PowerShell versions on the host meet minimum compatibility needed by the existing installer.
- The container base image CAN be a minimal Windows Server Core (LTSC 2022) image provided the harness installs PowerShell 7.2+ before invoking the installer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of installer test executions (pass or fail) publish a transcript and summary artifact accessible to maintainers.
- **SC-002**: 100% of failed executions include exit code, failing stage, and top-level error in the job output to support triage.
- **SC-003**: The installer test CI workflow MUST pass (green) for every release tag prior to publication (no release proceeds on a failing containerized installer test).

## Summary Structure Clarification (G7)

The `summary.json` produced by the harness distinguishes REQUIRED vs OPTIONAL fields:

REQUIRED (baseline MVP; absence is a failure of the harness):
Core Execution:
- `exitCode` (integer)
- `success` (boolean)
- `durationSeconds` (integer; rounded seconds)

Environment & Repro Context (schema-enforced for deterministic triage):
- `image` (string) – exact container image reference used
- `releaseTag` (string) – release under test
- `assetName` (string) – downloaded overlay asset filename
- `psVersion` (string) – PowerShell version inside container (ensures 7.2+)
- `startTime` / `endTime` (ISO 8601) – canonical timestamps (spec traceability optional fields do not duplicate these; see G16 forthcoming)

Rationale (G15): Align spec with existing schema guardrails so implementers have a single authoritative required set. These contextual fields materially aid reproducibility and are already enforced by `installer-test-summary.schema.json`.

OPTIONAL (enrichment; absence MUST NOT fail harness):
- `errorSummary` (string) – populated on failure scenarios
- `imagePullSeconds`, `containerCreateSeconds` – timing metrics (FR-007)
- `runId` (string) – short unique identifier per harness execution
- `imageDigest`, `timedPhases` – container/environment diagnostics
- `installedPrerequisites` (array) – tools successfully installed during run (e.g., choco, git, dotnet, InvokeBuild)
- `failedPrerequisites` (array) – tools that started installing but failed to complete
- `lastCompletedStep` (string) – name of last successful installer step before failure
- `guardCondition` (string) – guard condition triggering installer rejection (e.g., GitRepoRequired, PowerShellVersionUnsupported)
- Future additive fields (timing, identifiers) may be introduced without breaking consumers.

No schema version field is included in MVP. The presence of REQUIRED keys defines compatibility.

### Schema Alignment Note (G14)

The JSON schema file `contracts/installer-test-summary.schema.json` is intentionally a minimal validation guard and does not enumerate every OPTIONAL enrichment field (`imagePullSeconds`, `containerCreateSeconds`, `errorCategory`, `runId`, `startedAtUtc`, `endedAtUtc`). This is deliberate to avoid churn while OPTIONAL fields stabilize. The spec is the source of truth for OPTIONAL fields; the schema guarantees only baseline REQUIRED structure plus a few stable supplemental properties.

### Timestamp Clarification (G16)

`startTime` / `endTime` (required) are the canonical wall-clock timestamps recorded in the summary. Earlier exploratory optional names `startedAtUtc` / `endedAtUtc` are **not emitted in the MVP** to avoid duplication. Should richer traceability fields be desired later (e.g., separate host vs container times), they will be added under distinct optional keys following a new gap analysis.

### PowerShell Version Recording (G17)

`psVersion` MUST be captured after any attempted non-interactive upgrade initiated via `ALBT_AUTO_INSTALL=1` (FR-006). If the final detected version is below 7.2 after that attempt, the harness MUST:
- Set `errorCategory=missing-tool`
- Exit with code 6 (MissingTool precedence)
- Mark `success=false`
- Provide a concise `errorSummary` explaining required >=7.2 and detected version

The schema regex intentionally restricts to stable GA versions (no preview tags). Preview builds are out of scope for MVP; supporting them would require a separate gap decision to relax the pattern.

### Logs Object (G18)

The JSON schema defines an optional `logs` object with:
- `transcript` (required inside `logs` if object present): relative path or filename of the primary transcript (MVP: `install.transcript.txt`).
- `additional` (optional array): zero or more additional log artifact relative paths (e.g., `provision.log` on failure).

MVP Policy:
- Emitting the `logs` object is OPTIONAL; omission is acceptable.
- If emitted, it MUST reference files actually written under the harness output directory (no broken paths).
- `additional` SHOULD only include files present (do not list absent files).

Rationale: Keep core summary lean while providing a structured hook for tooling that may later surface multiple log channels without parsing free-form text.

### Duration Semantics (G19)

`durationSeconds` is the total wall-clock elapsed time (in whole seconds, floor-rounded) from immediately after initial harness configuration resolution (env + arguments) begins until just before process exit after writing `summary.json` and closing the transcript. It includes container pull, container creation, installer execution, and cleanup steps executed prior to summary write; it excludes any post-process artifact upload performed by external CI tooling. The harness MUST compute it via `(Get-Date) - $scriptStart` and cast/floor to an integer. Higher-resolution metrics (milliseconds or per-phase breakdown beyond explicitly listed optional timing fields) are out of scope for MVP and may be added later as optional fields after separate review.

### Run Identity (G22)

The optional `runId` field (now present in the schema) MAY be emitted as a short unique identifier (recommended 6–12 base36 characters) to correlate artifacts when multiple harness executions occur close in time. If omitted, consumers can rely on `startTime` + `image` + `releaseTag` for uniqueness. Implementations SHOULD only generate `runId` when no externally provided CI run identifier is readily available (keep output minimal). No other semantics depend on `runId`.

### Timing Fields Clarification (G23)

Optional `imagePullSeconds` and `containerCreateSeconds` are whole-second (floor-rounded) durations:
- `imagePullSeconds`: From initiation of the image pull command until pull completion (success or failure point producing timing if success).
- `containerCreateSeconds`: From start of the container create/start operation (after pull) until the container is running and ready to execute the installer command.

If either phase fails early (e.g., pull error) only the successfully completed prior phase timing MAY be present; missing values MUST NOT fail the harness. These timings are additive refinements; they do not need to sum exactly to `durationSeconds` because of overlap with setup/teardown or negligible overhead.

### Artifact Listing Clarification (G24)

The summary does not enumerate every artifact; artifact publication (transcript, summary itself, and failure-only `provision.log`) is an out-of-band concern of the harness and CI workflow. The existing optional `logs` object is the only structured in-summary reference point, providing the transcript path plus any additional log paths on failure. No `artifacts` array is introduced in the MVP to avoid duplication and churn. Future expansion will require a new gap if broader artifact manifesting is desired.

### Prerequisite Tracking (G26)

The harness parses container output for prerequisite installation diagnostic markers emitted by `bootstrap/install.ps1`:
- `[install] prerequisite tool="<name>" status="<status>"`
- `[install] step index=<n> name=<name>`
- `[install] guard <Condition>`

OPTIONAL fields populated from this parsing:
- `installedPrerequisites`: Array of tools that reached `status="installed"` (e.g., ["choco", "git", "dotnet"])
- `failedPrerequisites`: Array of tools with `status="installing"` but never reaching `installed` state
- `lastCompletedStep`: Name of the last step marker encountered (e.g., "Verify prerequisites")
- `guardCondition`: First guard condition encountered (e.g., "GitRepoRequired", "PowerShellVersionUnsupported")

Rationale: Provides structured failure diagnostics without requiring manual transcript parsing. When a prerequisite installation fails, maintainers can immediately identify which tool failed and at what step, enabling faster root-cause analysis.

The enhanced `errorSummary` on failure SHOULD include prerequisite context when available:
- Example: `"Installer exited with code 1 (failed prerequisites: dotnet) (last step: Verify prerequisites)"`

Absence of these fields does not indicate success; they are diagnostic enrichments only. The canonical failure indicator remains `success=false` and `exitCode≠0`.

### Exit Code Constraint (G25)

The schema now restricts `exitCode` to the set `[0,1,2,6]` (success, general failure, guard violation, missing tool). This enforces the current minimal taxonomy and prevents accidental emission of unintended codes. Introduction of additional standardized exit codes (e.g., 3–5 for analysis/contract/integration categories) will require a new gap and schema update before harness emission.

## Error Category Scope (Updated Post-Refactor)

The harness relies on standardized exit codes plus human-readable `errorSummary`. Asset integrity classification is no longer emitted directly by the harness (delegated to installer). If future experience shows value in restoring structured categories, a new gap will re-propose with schema changes.

## Cleanup Guarantees (G10)

The harness MUST attempt deterministic container cleanup exactly once at script end, regardless of success or failure (except when keep flag `ALBT_TEST_KEEP_CONTAINER` is set). Implementation notes (non-binding but guiding):
- Use a randomized container name to avoid collisions between rapid successive runs.
- Employ a try/finally structure around the main execution path to guarantee invocation of cleanup logic.
- Cleanup logic SHOULD be idempotent: repeated calls MUST NOT error if the container is already removed or never created.
- On cleanup failure (non-zero removal exit) the harness MAY log a warning but MUST still exit with the primary run exit code.

## Timeout & Retry Policy (G11 – Refactored)

Minimal harness policy:
- Network request timeout: 30 seconds (release metadata lookup only).
- Release metadata fetch retry: 1 additional attempt after fixed 2 second delay (see T034).
- Container pull/create: rely on Docker internal mechanisms; no harness-level retry.

Overlay download & digest retries are owned by the installer and outside harness scope after refactor. Harness maintains a lean responsibility set.

## Clarifications

### Session 2025-10-16

- Q: Which Windows base image should the container use? → A: Use `mcr.microsoft.com/windows/servercore:ltsc2022` and install PowerShell 7 during setup.

