# Feature Specification: Add Automated Tests for `install.ps1` (Bootstrap Installer Reliability & Guard Rails)

**Feature Branch**: `005-add-tests-for`
**Created**: 2025-09-16
**Status**: Draft
**Input**: User description: "Add tests for install.ps1 to ensure installer behavior and guard rails"

## Execution Flow (main)
```
1. Parse user description from Input
	→ If empty: ERROR "No feature description provided"
2. Extract key concepts from description
	→ Identify: actors (maintainers, contributors, CI), actions (execute installer, validate guards), data (environment vars, downloaded artifacts), constraints (idempotence, safety)
3. For each unclear aspect:
	→ Mark with [NEEDS CLARIFICATION: specific question]
4. Fill User Scenarios & Testing section
	→ If no clear user flow: ERROR "Cannot determine user scenarios"
5. Generate Functional Requirements
	→ Each requirement must be testable
	→ Mark ambiguous requirements
6. Identify Key Entities (if data involved)
7. Run Review Checklist
	→ If any [NEEDS CLARIFICATION]: WARN "Spec has uncertainties"
	→ If implementation details found: ERROR "Remove tech details"
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

### Section Requirements
- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation
When creating this spec from a user prompt:
1. **Mark all ambiguities**: Use [NEEDS CLARIFICATION: specific question] for any assumption you'd need to make
2. **Don't guess**: If the prompt doesn't specify something, mark it
3. **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
4. **Common underspecified areas**:
	- User types and permissions
	- Data retention/deletion policies
	- Performance targets and scale
	- Error handling behaviors
	- Integration requirements
	- Security/compliance needs

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a maintainer, I need confidence that the bootstrap installer script `install.ps1` performs required environment setup safely, predictably, and idempotently so contributors can onboard or CI can prepare environments without hidden failures, destructive side effects, or silent partial configuration.

### Acceptance Scenarios
1. **Given** a clean supported Windows environment with no prior bootstrap artifacts, **When** `install.ps1` is executed with default parameters, **Then** it completes successfully and reports a clear success summary (no silent failures).
2. **Given** the installer has already been run successfully, **When** it is executed again with the same parameters, **Then** it overwrites (replaces) previously installed overlay contents deterministically (treating prior overlay files as ephemeral) and exits successfully, guaranteeing the destination now matches the specified ref without requiring any separate update or force flag.
3. **Given** a required prerequisite (e.g., expected external tool or version) is missing, **When** the installer runs, **Then** it fails fast with a clear diagnostic explaining what is missing and how to resolve it.
4. **Given** an unsupported PowerShell version/environment, **When** the installer runs, **Then** it aborts with a clear guard‑rail message (no partial state changes) and non‑zero exit code.
5. **Given** a transient download/network failure during an external acquisition step, **When** the installer runs, **Then** it reports the failure cause clearly and exits non‑zero without leaving partially applied state that would cause later confusion.
6. **Given** the target path is not a git repository (no `.git` directory resolvable), **When** the installer is executed, **Then** it MUST abort (no file copies) with a guiding error explaining that installation requires an initialized git repo at the destination.
7. **Given** the installer completes successfully, **When** a subsequent script or test references expected outputs (e.g., created directory structure, configuration file), **Then** those outputs are present and valid (no missing postconditions).
8. **Given** an attempt to run the installer in a directory lacking required repository layout, **When** it is executed, **Then** it aborts with a clear context error (wrong working directory) rather than proceeding unpredictably.
9. **Given** a user supplies an unknown parameter or flag, **When** the installer parses arguments, **Then** it rejects the input with a helpful usage summary (not silent ignore).
10. **Given** a clean supported Ubuntu environment with PowerShell 7+ installed and a clean git working tree, **When** the installer is executed via `pwsh -File bootstrap/install.ps1`, **Then** it completes successfully with identical logical steps (semantic parity) and success summary as on Windows.
11. **Given** the installer has already run on Ubuntu, **When** it is executed again, **Then** deterministic scoped overwrite behavior (see Scenario 2) holds identically to Windows.
12. **Given** a simulated network failure on Ubuntu, **When** the installer retries or fails, **Then** the diagnostic format and failure semantics match Windows (differences only in platform-specific path formatting) ensuring cross-platform determinism.
13. **Given** path handling differences between Windows (`C:\...`) and Ubuntu (`/home/...`), **When** the installer logs resolved destination and source locations, **Then** logs remain structurally comparable (step numbering, success markers) enabling unified assertion patterns.
14. **Given** the target git repository contains any working tree modifications (staged, unstaged, or untracked files) in any path (including outside the overlay), **When** the installer is executed, **Then** it MUST abort with a guiding error instructing the user to commit, stash, remove, or otherwise clean the repository before running.
15. **Given** the installer is run concurrently once on Windows and once on Ubuntu against distinct clean repositories, **When** both complete, **Then** each succeeds independently without cross-environment interference.
16. **Given** the installer executes on Ubuntu, **When** it creates and later cleans up its temporary workspace under the default system temporary directory (no custom injection supported), **Then** creation succeeds under normal conditions and any failure (e.g., permission denial) produces a clear diagnostic analogous to Windows temp path failures.
17. **Given** an already-installed overlay (regardless of whether files match the source ref), **When** the same installer command is re-run (no separate update flag), **Then** it unconditionally re-downloads the source ref and overwrites the overlay subtree to ensure exact alignment (no version comparison or skip logic).

### Edge Cases
- Re-running after a partial previous failure (where any overlay files were copied before abort) is treated as a non-clean git state; the installer MUST abort with the same working tree not clean guidance (commit, stash, or reset) and does not attempt auto self-heal.
- Read-only file system or insufficient permissions should produce a clear permission-related failure without masking root cause.
- Large latency on external steps should surface progress feedback (avoid appearing hung) within acceptable responsiveness.

### Scope Boundaries (Non-Goals)
- Concurrency management (multiple simultaneous executions in the same repository path) is out of scope; the installer does not provide locking or collision detection.
- Optimizing away re-downloads for already up-to-date overlays is out of scope (every run overwrites, see FR-025).
- Automatic recovery / cleanup of partially applied previous attempts is out of scope (treated as non-clean state per Edge Cases).
- Offline/degraded caching behavior is out of scope; focus is on clear early fail.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: The system MUST provide automated test coverage validating successful default execution of `install.ps1` on a clean supported environment.
- **FR-002**: The system MUST validate deterministic overwrite behavior: a second execution after success MUST replace prior overlay contents so they exactly match the source ref (ephemeral overlay model) while preserving files outside the overlay scope.
- **FR-003**: The system MUST detect and assert correct non-zero exit with clear messaging when mandatory prerequisites are absent (guard‑rail validation).
- **FR-004**: The system MUST enforce environment/version guard rails (e.g., minimum supported PowerShell version) via tests that confirm failure mode clarity.
- **FR-005**: The system MUST validate that failure scenarios do not leave orphaned or partially applied critical artifacts (postcondition integrity check).
- **FR-006**: The system MUST confirm that all expected postconditions (directories, configuration artifacts, markers) exist after successful run.
- **FR-007**: The system MUST ensure that security / safety boundaries (restricted write locations, avoidance of privileged global modifications) are enforced and test-detectable.
- **FR-008**: The system MUST validate argument/parameter parsing rejects unsupported inputs and surfaces a usage/help summary.
- **FR-009**: The system MUST surface deterministic, human-readable diagnostics for each enforced guard so tests can assert on message patterns (stability requirement).
- **FR-010**: The system MUST measure and assert that a successful default run completes within an acceptable time threshold (performance guard for regressions). Acceptable time budget <30s.
- **FR-011**: The system MUST isolate test executions so that one failing or leaving artefacts does not impact subsequent runs (environment isolation requirement).
- **FR-012**: The system MUST document (within contributor guidance) the tested behavioral contract for `install.ps1` so future changes can be evaluated against it.
- **FR-013**: The system MUST provide a clear mapping from each test to a stated requirement (traceability) to ensure maintenance clarity.
- **FR-014**: The system MUST, on any failure while downloading or extracting the repository archive (e.g., unreachable host, DNS failure, HTTP error, timeout, corrupt/invalid archive), abort before copying overlay files, emit exactly one primary diagnostic line with stable prefix `[install] download failure` containing: `ref=<ref> url=<last-attempted-url> category=<CategoryName> hint=<actionable-remediation>`, where `category` is one of {NetworkUnavailable, NotFound, CorruptArchive, Timeout, Unknown}, and then exit non-zero after cleaning its temporary workspace.
- **FR-015**: The system MUST verify that a re-run after an intentional simulated partial failure (incomplete prior copy) is blocked identically to other non-clean states (no auto self-heal); tests assert abort with guidance to clean the repository first.
 - **FR-016**: The system MUST execute the same core test suite on both Windows and Ubuntu using PowerShell 7+ (`pwsh`) to validate cross-platform parity of outcomes and diagnostics.
 - **FR-017**: The system MUST ensure step numbering, success markers, and failure diagnostics remain structurally comparable across OSes (allowing only path formatting differences).
 - **FR-018**: The system MUST assert deterministic scoped overwrite on each OS (a successful first run followed by a second run that re-applies and fully realigns overlay contents to the source ref) without relying on prior OS-specific state.
 - **FR-019**: Each execution MUST create a unique dedicated temporary workspace under the system default temp directory, confine all transient acquisition artifacts (archive + extracted tree) to that workspace, and delete the entire workspace (best effort) before exit (success or failure). Tests MUST assert the workspace existed during execution, is removed afterward, and that no overlay files were copied to the destination prior to successful archive acquisition.
 - **FR-020**: The system MUST detect and fail clearly on permission or filesystem constraints on Ubuntu analogous to Windows failure semantics (message clarity & non-zero exit).
 - **FR-021**: The system MUST avoid embedding OS-specific logic in tests that would mask divergent installer behavior (tests assert platform-neutral outcomes where feasible).
 - **FR-022**: The system MUST validate cross-platform parity by running the same core test suite on Windows and Ubuntu and requiring all parity-designated assertions to pass on both; a simple successful test pass (no dedicated parity report artifact) is sufficient—any divergence causes test failure.
 - **FR-023**: The system MUST refuse to proceed (no copying actions) when the destination path is not a git repository (absence of `.git` or git status failure) and produce a guiding error message.
 - **FR-024**: The system MUST refuse to proceed when the destination git repository working tree is not clean (any staged, unstaged, or untracked changes present).
 - **FR-025**: The system MUST use a single command for initial install and all subsequent runs; every execution re-downloads the specified ref and overwrites the overlay subtree unconditionally (no version detection, no fast-skip optimization) while leaving files outside the overlay untouched.

### Acquisition Failure Categories (Reference)
Category definitions (classification only; no implementation detail implied):
- **NetworkUnavailable**: Name resolution or network connectivity failure prevents any download attempt from succeeding.
- **NotFound**: All candidate URLs for the specified ref return a definitive not-found response (e.g., HTTP 404) and no archive is obtained.
- **CorruptArchive**: An archive file downloads but cannot be expanded or is structurally invalid/empty for expected contents.
- **Timeout**: Download or extraction exceeds an expected time threshold and is aborted.
- **Unknown**: Any other unclassified exception; still reported via the standard diagnostic format.

Diagnostic Contract:
- Single primary line only: `"[install] download failure ref=<ref> url=<url> category=<CategoryName> hint=<hint>"`.
- `hint` provides a concise user action (e.g., "Check network connectivity and retry", "Verify ref name", "Retry later", "File appears corrupted; retry or specify a different ref").
- No overlay files may be present in destination after failure.
- Temporary workspace is removed (best effort) even on failure.

### Key Entities
- **Installer Session**: A conceptual execution instance with inputs (environment variables, parameters), side effects (created artifacts), and outputs (exit code, diagnostics).
- **Guard Rail**: A policy constraint that prevents unsafe or unsupported execution (version, permissions, context validity).
- **Postcondition Artifact**: Any file, directory, or marker whose presence/absence constitutes success criteria for a completed installer session.
 - **Ephemeral Overlay**: The copied `overlay/` payload whose contents are always treated as replaceable during subsequent installer executions; local modifications within this subtree are not preserved and MUST be overwritten.

### Temporary Workspace Behavior (Reference)
- Log (optionally) a line identifying the temp workspace path for test discovery.
- Workspace naming SHOULD be unique per run (e.g., random suffix) to avoid collisions.
- No residual workspace directories from successful or failed runs are acceptable; presence of a previous run's directory constitutes a failure.
- Overlay file copying MUST occur only after archive extraction integrity checks succeed.

---

## Review & Acceptance Checklist
*GATE: Automated checks run during main() execution*

### Content Quality
- [ ] No implementation details (languages, frameworks, APIs)
- [ ] Focused on user value and business needs
- [ ] Written for non-technical stakeholders
- [ ] All mandatory sections completed

### Requirement Completeness
- [ ] No [NEEDS CLARIFICATION] markers remain
- [ ] Requirements are testable and unambiguous
- [ ] Success criteria are measurable
- [ ] Scope is clearly bounded
- [ ] Dependencies and assumptions identified

---

## Execution Status
*Updated by main() during processing*

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified
- [ ] Review checklist passed

---

