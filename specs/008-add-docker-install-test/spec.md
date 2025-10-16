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

Release maintainers can trigger an automated check that provisions a clean Windows Docker container, runs the bootstrap install script end-to-end, and confirms the overlay installs without manual steps.

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
- **FR-002**: The harness MUST execute the bootstrap installer exactly as a new consumer would (download release artifact, copy overlay) without pre-populating caches or environment variables.
- **FR-003**: The harness MUST capture exit code, console transcript, and key installer artifacts, marking the test as failed when the installer exits non-zero.
- **FR-004**: The harness MUST publish captured diagnostics (logs, transcripts, summary) as part of the test result for both success and failure cases.
- **FR-005**: The harness MUST clean up containers and temporary assets after each run to avoid cross-test contamination and excessive resource use.
- **FR-006**: The harness MUST install PowerShell 7.2+ within the container when the selected base image does not preinstall it, ensuring `bootstrap/install.ps1` prerequisites are met.

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

- **SC-001**: Baseline installer runs inside the container finish successfully within 20 minutes in 95% of executions.
- **SC-002**: 100% of installer test executions (pass or fail) publish a transcript and summary artifact accessible to maintainers.
- **SC-003**: 100% of failed executions include exit code, failing stage, and top-level error in the job output to support triage within 10 minutes.
- **SC-004**: 100% of release cycles include at least one documented successful local dry run of the containerized test before publication.

## Clarifications

### Session 2025-10-16

- Q: Which Windows base image should the container use? → A: Use `mcr.microsoft.com/windows/servercore:ltsc2022` and install PowerShell 7 during setup.

