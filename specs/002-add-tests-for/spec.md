# Feature Specification: Bootstrap Installer Contract Tests

**Feature Branch**: `002-add-tests-for`
**Created**: 2025-09-11
**Status**: Draft
**Input**: User description: "Add tests for bootstrap install scripts (install.sh & install.ps1)"

## Overview
Provide a set of automated contract tests that validate the observable behavior of the bootstrap installer scripts responsible for copying the `overlay/` payload into a target project directory. The tests must ensure reliability, idempotence, clear failure signaling on prerequisite issues, and protection against regressions affecting downstream users who pipe the installer from a remote URL.

Primary stakeholders: Repository maintainers and any external project maintainers who rely on a predictable, side‑effect constrained bootstrap to onboard or update the build overlay.

Success is measured by: (a) repeatable green execution across supported scenarios, (b) deterministic detection of defined failure cases, (c) parity of documented behaviors between Linux (bash script) and Windows (PowerShell script) where applicable, (d) zero introduction of hidden state or unintended artifacts outside the destination directory.

## Out of Scope
- Performance benchmarking (installer speed not a goal here)
- Network resilience beyond simple success/failure of archive download
- Platform-specific Windows Explorer/GUI nuances (tests will execute `install.ps1` via `pwsh` on Ubuntu runners, which is sufficient for contract parity)
- Validation of the contents of `overlay/` beyond existence checks (functional behavior of overlay scripts is covered elsewhere)
- Use of the unsupported `--ref` parameter (intentionally excluded from tests to discourage reliance)
- Simulated network fetch failure scenarios (excluded to avoid flakiness; only positive-path download is covered)
- Concurrency / simultaneous multi-invocation behavior (explicitly excluded; single-invocation contract focus)

## Assumptions
- Public GitHub archive endpoints remain stable in URL patterns already used.
- Internet access is available during the installer test execution for positive download cases.
- A temporary, writable filesystem area is available for sandboxed destinations.

## User Scenarios & Testing *(mandatory)*

### Primary User Story
A maintainer (or user) wants to bootstrap or update the AL build overlay in an existing or new repository directory by piping or running the installer script. They expect required files to appear, existing copies to be updated safely when re-run, and clear errors if prerequisites are missing or an invalid ref is specified.

### Acceptance Scenarios
1. **Given** an empty destination directory, **When** the installer runs with defaults, **Then** the `overlay/` contents are present in the destination with all expected top-level files (e.g., `Makefile`, `scripts/make/linux/build.sh`).
2. **Given** a directory that already contains a prior installation, **When** the installer is re-run with defaults, **Then** the result is idempotent: files are updated in place without duplication and the command exits successfully.
3. **Given** a valid git repository as destination, **When** the installer runs, **Then** it completes without altering the git metadata and warns only when appropriate (no false warning about git absence).
4. **Given** a non-git directory, **When** the installer runs, **Then** it succeeds and emits a non-fatal warning about missing git but still copies files.
5. **Given** a custom destination path that does not yet exist, **When** the installer is invoked with `--dest`, **Then** the path is created and populated.
6. **Given** prerequisites satisfied except unzip (but python available), **When** the installer runs, **Then** it falls back to python extraction and succeeds.
7. **Given** prerequisites satisfied except both unzip and python, **When** the installer runs, **Then** it fails fast with a clear error about extraction prerequisites.
8. **Given** the destination already contains extraneous files, **When** the installer runs, **Then** those unrelated files remain untouched.

### Edge Cases
- Destination path containing spaces. Should still resolve and copy successfully.
// Removed ref-related edge case per guidance.
- Attempt to run in a read-only destination should fail with a permission error surfaced by the script (no silent partial copy).

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: The test suite MUST verify successful initial installation into an empty destination directory using default parameters.
- **FR-002**: The test suite MUST verify idempotent re-run (subsequent execution overwrites/updates without duplicate or stale artifacts and exits zero).
- **FR-003**: The test suite MUST validate behavior in both git and non-git destination contexts (warning only in non-git case, no failure).
- **FR-004**: The test suite MUST confirm custom destination creation when the specified path does not pre-exist.
- **FR-005**: The test suite MUST exercise prerequisite branching ensuring fallback to python extraction when unzip is absent.
- **FR-006**: The test suite MUST assert explicit failure when neither unzip nor python3 are available (prerequisite error message).
- **FR-007**: The test suite MUST ensure unrelated pre-existing files in destination remain unchanged after installation.
- **FR-008**: The test suite MUST confirm repeated runs do not mutate git metadata (e.g., no `.git` modifications) in a repository destination.
- **FR-009**: The test suite MUST verify the installer reports count of copied files (or equivalent success indicator) on success.
- **FR-010**: The test suite MUST ensure that error conditions produce non-zero exit codes (no silent success on failure paths).
- **FR-011**: The test suite MUST execute both `bootstrap/install.sh` and `bootstrap/install.ps1` (via `pwsh`) in CI, asserting parity of observable behaviors (exit codes, warnings, idempotence, file copy results).
- **FR-012**: The suite MUST avoid external side effects outside of temporary working directories (clean teardown of temp artifacts).

### Non-Functional Requirements (Supporting)
- **NFR-001**: Tests MUST complete within a bounded, short duration (target < 2 minutes aggregate) to keep CI fast.
- **NFR-002**: Tests MUST be deterministic (no reliance on timing races or external mutable services beyond GitHub archive response).
- **NFR-003**: Tests MUST isolate state (unique temp directories per case) to prevent cross-test contamination.

### Open Questions
// (None at this time – all prior clarification items resolved or deferred out of scope)

## Review & Acceptance Checklist

### Content Quality
- [x] No implementation details (languages, frameworks, APIs) beyond necessary behavioral descriptions
- [x] Focused on user value (reliable bootstrap) and business needs (regression prevention)
- [x] Written for non-technical stakeholders (behavioral framing)
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous (post-clarification)
- [x] Success criteria are measurable (exit codes, file presence, warnings)
- [x] Scope is clearly bounded (installer behavior only)
- [x] Dependencies and assumptions identified

## Execution Status

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [ ] Entities identified (not applicable – no persistent domain entities)
- [ ] Review checklist passed (pending clarification resolution)

