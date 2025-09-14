 # Feature Specification: PowerShell‑Only Build Script Consolidation

 **Feature Branch**: `003-powershell-only-build`
 **Created**: 2025-09-14
 **Status**: Draft
 **Input**: User description: "# PowerShell‑Only Build Scripts: Why and What\n\n## Why\n\n- Single Toolchain: Maintaining both Bash and PowerShell duplicates logic and increases drift risk. Consolidating on PowerShell 7.2+ yields one implementation to review, test, and secure across Windows and Linux.\n- Parity by Design: PowerShell offers consistent cmdlets and error semantics on both OSes, helping us keep behavior identical for build, clean, show-config, and show-analyzers.\n- Testability: Pester enables first‑class unit, contract, and integration testing without extra dependencies, improving confidence before removing Bash scripts.\n- Security and Predictability: Forcing invocation through make ensures scripts run with a controlled environment and known entrypoints, preventing accidental or agent-driven direct execution that might skip preconditions.\n- Quality Gate: PSScriptAnalyzer provides mandatory static analysis to enforce style and correctness before runtime.\n\n## What\n\n- Scope\n  - Replace Bash with PowerShell in overlay/scripts/make, with no linux or windows subfolders.\n  - Guard all make-target scripts behind an environment variable check.\n  - Keep overlay/scripts/next-object-number.ps1 callable directly with no guard.\n  - Add comprehensive Pester suites, contract and integration, and make them pass on Windows and Linux.\n  - Enforce PSScriptAnalyzer as a continuous integration gate.\n\n- Entrypoints make-only\n  - overlay/scripts/make/build.ps1\n  - overlay/scripts/make/clean.ps1\n  - overlay/scripts/make/show-config.ps1\n  - overlay/scripts/make/show-analyzers.ps1\n\n- Direct-Use Tool exempt from guard\n  - overlay/scripts/next-object-number.ps1\n\n- Common Conventions\n  - PowerShell minimum 7.2\n  - Headers include requires Version 7.2, Set-StrictMode Version Latest, and ErrorActionPreference Stop\n  - Consistent verbosity honoring -Verbose and VERBOSE environment variable\n  - No network calls in overlay scripts or tests\n  - Cross‑platform paths via Join-Path and UTF‑8 encoding\n\n- Guard Policy\n  - Environment variable ALBT_VIA_MAKE\n  - Behavior if missing, exit code 2 with concise Run via make guidance\n  - Applies to help as well, flags -h, --help, -?\n  - Ensure ALBT_VIA_MAKE is scoped to the recipe call and removed afterward, not left in the user environment\n\n- Testing\n  - Contract tests verify CLI surfaces, guard behavior, flags, exit codes, and help\n  - Integration tests invoke targets through make on both OSes, no direct script calls\n  - Use TestDrive for hermetic temp workspaces and mock external tools\n\n- Static Analysis\n  - Mandatory PSScriptAnalyzer using .config ScriptAnalyzerSettings.psd1\n  - CI fails fast on violations before running tests\n\n- CI\n  - Matrix ubuntu-latest and windows-latest with pwsh 7.2+\n  - Ensure GNU make available on both\n  - Order PSSA, then Pester contract, then Pester integration, and publish test artifacts\n\n- Non‑Goals and Out of Scope\n  - Changing analyzers or bundling them\n  - Altering bootstrap installer UX beyond updating docs to PowerShell‑only\n  - Adding new network dependencies\n  - Rewriting consumer repos pipelines beyond advising make usage\n\n- Success Criteria\n  - All make-target scripts pass contract and integration tests on both OSes\n  - CI is green with PSSA gate enforced\n  - Bash scripts can be removed without user visible regressions\n  - Documentation clearly states make only enforcement and PS 7.2 requirement"

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a build maintainer, I want a single cross‑platform build toolkit invoked uniformly through `make` so that I reduce maintenance effort, ensure identical behavior on Windows and Linux, and gain higher confidence through static analysis and automated tests before releasing updates.

### Acceptance Scenarios
1. Given a developer runs `make build` without having set any special environment variables, When `make` invokes the PowerShell build entrypoint, Then the script executes successfully provided PowerShell 7.2+ is available and sets and clears the guard variable internally.
2. Given a user tries to execute a guarded script directly (e.g., build script) in a PowerShell session without `ALBT_VIA_MAKE`, When they run it, Then it exits with code 2 and a concise message directing them to invoke via `make`.
3. Given a user invokes a guarded script requesting help (e.g., `-h`), When `ALBT_VIA_MAKE` is absent, Then the same guard enforcement occurs (exit code 2) with guidance.
4. Given the direct‑use utility script (object number helper), When a user executes it directly, Then it runs without requiring the guard variable.
5. Given static analysis violations exist, When CI runs, Then the pipeline fails before executing any contract or integration tests.
6. Given contract tests and integration tests pass on both supported operating systems, When CI completes, Then the feature is considered validated for removing Bash scripts.
7. Given verbosity is requested via `-Verbose` flag or `VERBOSE` environment variable, When scripts run, Then additional diagnostic output is emitted consistently across commands.

### Edge Cases
- PowerShell version below 7.2 encountered → script aborts immediately via `#requires -Version 7.2` (no custom runtime duplication); documented behavior and test expectations detailed in Version Enforcement Strategy section.
- Invocation on an unsupported platform (anything other than Windows or Ubuntu-latest CI images) or absence of GNU make → build should fail fast with clear message identifying supported targets (Windows + Ubuntu) and requirement for GNU make.
- `ALBT_VIA_MAKE` already set in user shell before any call → ensure toolkit does not rely on persistent value after script completion; each guarded script MUST unset (or avoid exporting) the variable on exit to prevent leakage.
- Missing PSScriptAnalyzer (or other required tooling such as Pester) on developer machine → build MUST fail fast with clear guidance to install the missing module; no silent skip or pass allowed.
- Test execution on an offline machine (no network) → all tests must still pass (no hidden network calls).
- Simultaneous parallel `make` invocations → guard variable scoping must not cause cross‑process interference.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: The toolkit SHALL consolidate platform build, clean, configuration display, and analyzer listing into a single cross‑platform PowerShell implementation.
- **FR-002**: The toolkit SHALL expose build, clean, show configuration, and show analyzers commands invocable only through `make` (guarded entrypoints).
- **FR-003**: Guarded scripts SHALL refuse direct invocation when `ALBT_VIA_MAKE` is not set, exiting with code 2 and emitting a concise remediation message.
- **FR-004**: Guard enforcement SHALL also apply to help requests (`-h`, `--help`, `-?`).
- **FR-005**: The direct‑use utility (object number helper) SHALL remain executable without guard enforcement.
- **FR-006**: All scripts SHALL support verbosity controlled by standard PowerShell `-Verbose` and by a `VERBOSE` environment variable.
- **FR-007**: Scripts SHALL avoid network access during normal operation and during all automated tests.
- **FR-008**: The system SHALL provide a static analysis gate that must pass before executing any Pester test phase in CI.
- **FR-009**: The CI pipeline SHALL run on Windows and Linux using a supported PowerShell version ≥ 7.2.
- **FR-010**: Contract tests SHALL validate command surfaces, guard behavior, exit codes, and help output.
- **FR-011**: Integration tests SHALL exercise commands exclusively via `make` and confirm guard isolation.
- **FR-012**: Tests SHALL be hermetic, using temporary isolated workspaces and mocks for external tool presence.
- **FR-013**: The build system SHALL guarantee `ALBT_VIA_MAKE` scope is limited to the lifetime of a single guarded invocation (no persistence in parent shell; parallel invocations isolated).
- **FR-014**: On unsupported PowerShell versions, scripts SHALL terminate before any user logic via `#requires -Version 7.2`, producing the native PowerShell error message (this satisfies the “clear message” requirement; no secondary runtime check implemented to avoid redundancy).
- **FR-015**: Documentation SHALL clearly communicate PowerShell‑only support, guard policy, and the minimum version requirement.
- **FR-016**: Removing legacy Bash scripts SHALL cause no observable regression in existing user workflows (functional parity maintained).
- **FR-017**: Static analysis failure SHALL exit with code 3 (per standardized exit code mapping) and abort subsequent test phases.
- **FR-018**: CI artifact publishing SHALL include test results for both contract and integration phases.
- **FR-019**: The specification SHALL avoid introducing new network dependencies or bundling analyzer binaries.
- **FR-020**: Static analysis SHALL NOT be bypassed locally or in CI; any attempt to skip or suppress PSScriptAnalyzer results MUST terminate with exit code 3 and an explicit refusal message.
- **FR-021**: Version enforcement design SHALL avoid dual mechanisms; any future need for a custom message MUST justify benefits over native `#requires` and be applied consistently across all guarded scripts.
- **FR-022**: Supported execution environments are limited to (a) Windows (GitHub Actions windows-latest image and comparable local Windows hosts) and (b) Ubuntu (GitHub Actions ubuntu-latest image and comparable local Linux hosts). Attempts to run core `make` targets without GNU make or on other platforms SHALL terminate with a clear unsupported-platform error.
- **FR-023**: If mandatory tooling (PSScriptAnalyzer, Pester, or future enumerated required modules) is absent, the build or test phases SHALL fail with an explicit missing-tool error (no auto-install, no downgrade to warnings, no partial pass).

*Ambiguities / Clarifications Needed*
(All previously open items about exit code mapping, parallel runs, and help discoverability have been resolved by Decisions section.)

### Key Entities *(include if feature involves data)*
- **Build Command Entrypoint**: Logical interface representing the primary build action (compiles, packages). Not concerned with underlying script mechanics.
- **Guard Mechanism**: Validation layer ensuring invocation context is mediated by `make` via a transient environment variable.
- **Static Analysis Gate**: Quality control stage ensuring style and correctness prior to executing any tests.
- **Contract Test Suite**: Collection verifying externally observable command behavior (arguments, exits, messages).
- **Integration Test Suite**: Cross‑platform validation ensuring full workflow parity and isolation from direct script calls.
- **Direct Utility Tool**: Single unguarded command supporting object number allocation logic for consumers.
- **CI Pipeline Flow**: Orchestrated stages (analysis → contract tests → integration tests → artifact publish) across Windows and Linux.

---

## Review & Acceptance Checklist
*GATE: Automated checks run during main() execution*

### Content Quality
- [x] No implementation details (only externally observable behaviors and exit codes)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

---

## Version Enforcement Strategy

### Objective
Guarantee that all guarded (and utility) scripts fail fast on unsupported PowerShell versions while minimizing maintenance overhead and avoiding divergent behaviors between local and CI environments.

### Options Considered
1. `#requires -Version 7.2` ONLY (Chosen)
	- Pros: Built-in, zero maintenance, halts before parsing unsupported syntax, consistent error format, universally testable.
	- Cons: Error message text is controlled by PowerShell and not brand-customizable.
2. `#requires` + Runtime Version Check
	- Pros: Allows customized, friendlier messaging.
	- Cons: Redundant (runtime block never executes on older hosts if advanced syntax used); adds boilerplate to every script; risk of drift.
3. Runtime Check ONLY (no `#requires`)
	- Pros: Fully custom messaging.
	- Cons: Parser may fail earlier if newer syntax appears; inconsistent failure patterns; easier to accidentally bypass in refactors.

### Decision
Adopt Option 1: rely exclusively on `#requires -Version 7.2` in every entrypoint (guarded scripts and the direct-use utility). The native error is deemed sufficiently clear. FR-014 and FR-021 codify this.

### Rationale
- Ensures immediate stop before any side effects.
- Eliminates duplicated logic and reduces test surface.
- Aligns with PowerShell best practices for module / script minimum version declaration.
- Keeps scripts succinct, improving readability and decreasing lint noise.

### Developer Experience
When a user on (for example) PowerShell 7.1 runs a guarded script directly or via `make`, the host emits an error similar to:
`The script 'build.ps1' cannot be run because it contained a '#requires' statement for PowerShell 7.2.`

### Testing Approach
Contract test (skipped by default in environments already ≥7.2) may simulate the error by invoking a subshell with a deliberately lower version if available, or by static assertion that `#requires -Version 7.2` appears at the top of each script. Acceptance relies on presence and correctness of the directive rather than executing under an old runtime in CI (since hosted images already supply ≥7.2).

### Future Change Guidance
If later a custom message is required, introduce a lightweight bootstrap wrapper (without advanced syntax) performing a manual version check before dot-sourcing the implementation file—applied uniformly across all entrypoints. This change would supersede FR-021 and require updating the test matrix and documentation.

### Open Questions (if customization ever revisited)
- Should custom messaging localize or link to upgrade docs?
- Would a bootstrap affect script analyzer rules or introduce measurable startup latency?

---

## Decisions (Finalized)

### Exit Code Mapping (Choice 1B)
| Condition | Exit Code |
|-----------|-----------|
| Success | 0 |
| Guard violation (direct invocation without ALBT_VIA_MAKE) | 2 |
| Static analysis failure (PSScriptAnalyzer) | 3 |
| Contract test failure | 4 |
| Integration test failure | 5 |
| Missing required tooling (PSScriptAnalyzer, Pester, etc.) | 6 |
| Any other unexpected internal error | >6 (native PowerShell or script-specific) |

Rationale: Provides granular CI branching and diagnostics without excessive range usage.

### Parallel Runs & Guard Scope (Choice 2A)
Policy: `ALBT_VIA_MAKE` is set only in the environment of each individual process spawn by `make` and is never exported globally nor reused across invocations. Scripts MUST NOT re-export or persist it. Parallel invocations are isolated by process boundary—no token randomization required.

### Help Discoverability (Choice 3C)
Direct (unguarded) invocation with help flags prints a terse stub (3–5 lines) instructing the user to run `make help` (or a documented make target) for full usage. Full detailed help is only displayed when guard condition is satisfied (invoked via make). This preserves enforcement while offering immediate orientation.

---

## Additional Functional Requirements (Decisions Incorporated)

- **FR-024**: The system SHALL implement the standardized exit code mapping (1B) defined in the Decisions section.
- **FR-025**: Unguarded help requests SHALL output only a stub redirecting to guarded `make` help; full help content SHALL require guard context (Choice 3C implementation).

---

---

## Execution Status
*Updated by main() during processing*

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified
- [x] Review checklist passed

---

## Success Metrics

- Guard Rejection: 100% of direct guarded script invocations without `ALBT_VIA_MAKE` exit with code 2.
- Static Analysis Quality: 0 PSScriptAnalyzer Error or Warning rule violations in CI (strict mode). Local runs MUST fail if any violation exists.
- Test Pass Rate: 100% passing contract and integration tests on Windows and Ubuntu.
- Cross-Platform Parity: Normalized (whitespace + line ending neutral, non-timestamp) output of build/clean/show-config/show-analyzers identical across Windows and Ubuntu; mismatch triggers integration test failure (exit 5).
- Performance: Average `make build` (warm cache, no publish) ≤ 20s; 95th percentile ≤ 30s on both CI OS images.
- Missing Tool Detection: Absence of required tooling produces exit code 6 within 1 second of start.
- Help Stub: Unguarded help output ≤ 5 lines and includes redirect to `make help`.
- Environmental Leakage: Post-run environment MUST NOT retain `ALBT_VIA_MAKE` (validated by contract test).

## Dependencies & Assumptions

- PowerShell 7.2+ installed on all supported hosts.
- GNU make available (`make --version` reports "GNU").
- Required modules pre-installed: PSScriptAnalyzer (min version to be documented), Pester ≥ 5.0.0.
- Git present if ancillary metadata retrieval is later required (not mandatory for core build path).
- No outbound network access required for normal operations or tests.
- File system supports UTF-8; scripts do not require elevated privileges.
- CI environments: GitHub Actions `windows-latest` and `ubuntu-latest` images assumed representative for consumers.
- Parallel invocations rely on process isolation; no shared mutable state.
