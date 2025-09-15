# Feature Specification: PowerShell‑Only Build Script Consolidation (Relocation & Reuse Update)

**Feature Branch**: `003-powershell-only-build`
**Created**: 2025-09-14
**Revised**: 2025-09-15 (directive change: reuse existing scripts)
**Status**: Draft (updated)
**Summary of Change**: The initial draft assumed net‑new PowerShell script creation. Direction is updated to RELOCATE existing Windows PowerShell scripts to a neutral location and DELETE Bash scripts, minimizing churn and preserving proven behavior while adding guard, verbosity normalization, and standardized exit codes.

## Why (Core Drivers)
- Eliminate duplication & drift (remove Bash variants).
- Reuse stable, already‑working Windows PowerShell logic (reduced risk vs rewrite).
- Achieve cross‑platform support through PowerShell 7+ (no per‑OS folders).
- Strengthen quality gates (Pester + PSScriptAnalyzer) with a single surface.
- Reduce overlay footprint (fewer files shipped to consumers).

## Scope (Revised)
| Action | Detail |
|--------|--------|
| Relocate | Move `overlay/scripts/make/windows/*.ps1` up one level to `overlay/scripts/make/` (flatten) keeping filenames (`build.ps1`, `clean.ps1`, etc.). |
| Inline | Collapse any helper functions from `windows/lib/*.ps1` into each script (only small necessary portions) to avoid shipping a `lib/` directory post‑relocation. |
| Guard | Add `ALBT_VIA_MAKE` guard to relocated scripts (if not already present). |
| Delete | Remove entire `overlay/scripts/make/linux/` directory and its Bash scripts in this feature branch. |
| Preserve | Keep `overlay/scripts/next-object-number.ps1` unguarded (only minor consistency tweaks if needed). |
| Enhance | Add standardized exit codes, verbosity env var support, deterministic config output ordering, help stub behavior. |

Source baseline behavior is documented in [inventory-windows-scripts.md](file:///d:/repos/al-build-tools/specs/003-powershell-only-build/inventory-windows-scripts.md) to anchor relocation and parity (FR-025).

## Entrypoints (Post‑Relocation, Guarded)
- `overlay/scripts/make/build.ps1`
- `overlay/scripts/make/clean.ps1`
- `overlay/scripts/make/show-config.ps1`
- `overlay/scripts/make/show-analyzers.ps1`

## Direct Utility (Unguarded)
- `overlay/scripts/next-object-number.ps1`

## Guard Policy
- Variable: `ALBT_VIA_MAKE` must exist or script exits 2 with guidance `Run via make (e.g., make build)`.
- Help flags without guard still produce guard message (no full help bypass).
- Make recipes set & scope the variable; scripts must not persist it.

## Conventions & Constraints
- PowerShell `#requires -Version 7.2` at top of each script.
- `Set-StrictMode -Version Latest`; `$ErrorActionPreference='Stop'` retained.
- No network calls added.
- Path handling standardized (`Join-Path`, no hard‑coded backslashes).
- Verbosity: either `VERBOSE=1 make build` or pass-through `-Verbose` flag.
- Exit code mapping reused from original spec (guard=2, analysis=3, contract=4, integration=5, missing tool=6).

## Testing Emphasis
- Contract tests target guard behavior, exit codes, help stub, verbosity, and parity (relocated vs baseline Windows output) executed inside a temporary fixture AL project with the overlay copied in.
- Integration tests run from the fixture AL project and ensure cross‑platform identical (normalized) outputs and environment isolation; build parity runs only when a real AL compiler is discovered, otherwise tests are marked skipped with rationale.
- Pester & PSScriptAnalyzer remain CI gates; no tests depend on removed Bash scripts.

## Success Criteria (Relocation)
- Bash directory removed; Make targets function unchanged for users.
- Relocated scripts pass all contract & integration tests on Windows + Ubuntu.
- No regression in documented behavior; parity confirmed for key outputs.
- Documentation updated: no lingering references to `linux/` Bash scripts.
- Static analysis clean; no new warnings from inlining helpers.

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a build maintainer, I want a single cross‑platform build toolkit invoked uniformly through `make` so that I reduce maintenance effort, ensure identical behavior on Windows and Linux, and gain higher confidence through static analysis and automated tests before releasing updates.

### Acceptance Scenarios
1. Given a developer runs `make build` from within a valid AL project without having set any special environment variables, When `make` invokes the PowerShell build entrypoint, Then the script executes successfully provided PowerShell 7.2+ is available and sets and clears the guard variable internally.
2. Given a user tries to execute a guarded script directly (e.g., build script) in a PowerShell session without `ALBT_VIA_MAKE`, When they run it, Then it exits with code 2 and a concise message directing them to invoke via `make`.
3. Given a user invokes a guarded script requesting help (e.g., `-h`), When `ALBT_VIA_MAKE` is absent, Then the same guard enforcement occurs (exit code 2) with guidance.
4. Given the direct‑use utility script (object number helper), When a user executes it directly, Then it runs without requiring the guard variable.
5. Given static analysis violations exist, When CI runs, Then the pipeline fails before executing any contract or integration tests.
6. Given contract tests and integration tests pass on both supported operating systems, When CI completes, Then the feature is considered validated for removing Bash scripts.
7. Given verbosity is requested via `-Verbose` flag or `VERBOSE` environment variable, When scripts run, Then additional diagnostic output is emitted consistently across relocated commands.
8. Given previously functioning Windows scripts, When the relocated versions execute via `make`, Then normalized outputs (ignoring line endings) match prior behavior (parity) for core targets (build, clean, show-config, show-analyzers). Build parity is executed only when the AL compiler is discovered; otherwise the scenario is marked skipped with rationale.

### Edge Cases
- PowerShell version below 7.2 encountered → script aborts immediately via `#requires -Version 7.2` (no custom runtime duplication); documented behavior and test expectations detailed in Version Enforcement Strategy section.
- Invocation on an unsupported platform (anything other than Windows or Ubuntu-latest CI images) or absence of GNU make → build should fail fast with clear message identifying supported targets (Windows + Ubuntu) and requirement for GNU make.
- `ALBT_VIA_MAKE` already set in user shell before any call → ensure toolkit does not rely on persistent value after script completion; each guarded script MUST unset (or avoid exporting) the variable on exit to prevent leakage.
- Missing PSScriptAnalyzer (or other required tooling such as Pester) on developer machine → build MUST fail fast with clear guidance to install the missing module; no silent skip or pass allowed.
- Test execution on an offline machine (no network) → all tests must still pass (no hidden network calls).
- Simultaneous parallel `make` invocations → guard variable scoping must not cause cross‑process interference.

## Requirements *(mandatory)*

### Functional Requirements (Noting CI-only vs Shipped Behavior)
- **FR-001**: The toolkit SHALL consolidate platform build, clean, configuration display, and analyzer listing into a single cross‑platform PowerShell implementation.
- **FR-002**: The toolkit SHALL expose build, clean, show configuration, and show analyzers commands invocable only through `make` (guarded entrypoints).
- **FR-003**: Guarded scripts SHALL refuse direct invocation when `ALBT_VIA_MAKE` is not set, exiting with code 2 and emitting a concise remediation message.
- **FR-004**: Guard enforcement SHALL also apply to help requests (`-h`, `--help`, `-?`).
- **FR-005**: The direct‑use utility (object number helper) SHALL remain executable without guard enforcement.
- **FR-006**: All scripts SHALL support verbosity controlled by standard PowerShell `-Verbose` and by a `VERBOSE` environment variable.
- **FR-007**: Scripts SHALL avoid network access during normal operation and during all automated tests.
- **FR-008**: The system SHALL provide a static analysis gate (CI-only) that must pass before executing any Pester test phase.
- **FR-009**: The CI pipeline SHALL run on Windows and Linux using a supported PowerShell version ≥ 7.2.
- **FR-010**: Contract tests SHALL validate command surfaces, guard behavior, exit codes, and help output.
- **FR-011**: Integration tests SHALL execute inside a temporary fixture AL project (overlay copied in) and exercise commands exclusively via `make`, confirming guard isolation.
- **FR-012**: Tests SHALL be hermetic, using temporary isolated workspaces; external tool presence (e.g., AL compiler) is not required, and build parity is conditional on discovery.
- **FR-013**: The build system SHALL guarantee `ALBT_VIA_MAKE` scope is limited to the lifetime of a single guarded invocation (no persistence in parent shell; parallel invocations isolated).
- **FR-014**: On unsupported PowerShell versions, scripts SHALL terminate before any user logic via `#requires -Version 7.2`, producing the native PowerShell error message (this satisfies the “clear message” requirement; no secondary runtime check implemented to avoid redundancy).
- **FR-015**: Documentation SHALL clearly communicate PowerShell‑only support, guard policy, and the minimum version requirement.
- **FR-016**: Removing legacy Bash scripts SHALL cause no observable regression in existing user workflows (functional parity maintained).
- **FR-017**: Static analysis failure in CI SHALL exit with code 3 (per standardized exit code mapping) and abort subsequent test phases.
- **FR-018**: CI artifact publishing SHALL include test results for both contract and integration phases.
- **FR-019**: The specification SHALL avoid introducing new network dependencies or bundling analyzer binaries.
- **FR-020**: Static analysis SHALL NOT be bypassed locally or in CI; any attempt to skip or suppress PSScriptAnalyzer results MUST terminate with exit code 3 and an explicit refusal message.
- **FR-021**: Version enforcement design SHALL avoid dual mechanisms; any future need for a custom message MUST justify benefits over native `#requires` and be applied consistently across all guarded scripts.
- **FR-022**: Supported execution environments are limited to (a) Windows (GitHub Actions windows-latest image and comparable local Windows hosts) and (b) Ubuntu (GitHub Actions ubuntu-latest image and comparable local Linux hosts). Attempts to run core `make` targets without GNU make or on other platforms SHALL terminate with a clear unsupported-platform error.
- **FR-023**: If mandatory tooling (PSScriptAnalyzer, Pester, or future enumerated required modules) is absent, the build or test phases SHALL fail with an explicit missing-tool error (no auto-install, no downgrade to warnings, no partial pass).

*Ambiguities / Clarifications Needed*
(All previously open items about exit code mapping, parallel runs, and help discoverability have been resolved by Decisions section.)

### Key Entities *(Adjusted)*
- **Build Command Entrypoint**: Inline guarded script.
- **Guard Mechanism**: Inline env var check at top of each guarded script (no shared shipped module).
- **Static Analysis Gate**: CI pipeline stage (not a runtime overlay artifact).
- **Contract Test Suite**: Internal repository tests (not shipped) verifying observable behavior.
- **Integration Test Suite**: Internal repository tests ensuring cross-platform parity via `make`.
- **Direct Utility Tool**: Unguarded `next-object-number.ps1` script.
- **CI Pipeline Flow**: Stages (analysis → contract tests → integration tests → artifact publish).

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

### Version Enforcement Strategy

### Options Considered
1. `#requires -Version 7.2` ONLY (Chosen)
	- Pros: Built-in, zero maintenance, halts before parsing unsupported syntax, consistent error format, universally testable.
	- Cons: Error message text is controlled by PowerShell and not brand-customizable.
2. `#requires` + Runtime Version Check
	- Pros: Allows customized, friendlier messaging.
	- Cons: Redundant; runtime block never executes on older hosts if advanced syntax used.
3. Runtime Check ONLY (no `#requires`)
	- Pros: Fully custom messaging.
	- Cons: Parser may fail earlier; inconsistent failure patterns; easier to bypass.

### Decision
Adopt Option 1: rely exclusively on `#requires -Version 7.2` in every entrypoint (guarded scripts and the direct-use utility). The native error is deemed sufficiently clear. FR-014 and FR-021 codify this.

Benefits:
- Immediate stop before any side effects.
- Eliminates duplicated runtime version logic.
- Aligns with PowerShell best practices.
- Keeps scripts succinct, aiding readability and analyzer clarity.

### Developer Experience
When executed on <7.2 the host emits: `The script 'build.ps1' cannot be run because it contained a '#requires' statement for PowerShell 7.2.`

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
- Missing Tool Detection: Absence of required tooling produces exit code 6 within 1 second of start.
- Help Stub: Unguarded help output ≤ 5 lines and includes redirect to `make help`.
- Environmental Leakage: Post-run environment MUST NOT retain `ALBT_VIA_MAKE` (validated by contract test).

## Configuration & Discovery (Contracts Overview)

This feature formalizes a set of externally observable contracts (C1–C14) that implementation and tests MUST honor. Detailed normative definitions live in `contracts/README.md`; this section summarizes intent and rationale.

| ID | Theme | Summary |
|----|-------|---------|
| C1 | Make Targets | `build`, `clean`, `show-config`, `show-analyzers`, `next-object-number` (unguarded) are the only public entrypoints. |
| C2 | Variable Precedence | `WARN_AS_ERROR`, `RULESET_PATH`, future build vars inherited from `make` environment; scripts do not override unless absent. |
| C3 | Ruleset Resolution | If `RULESET_PATH` names an existing non‑empty file it is passed via `/ruleset:`; otherwise silently skipped with warning. No hard failure. |
| C4 | Warnings-as-Errors | Treat warnings as errors when `WARN_AS_ERROR` in (`1`,`true`,`yes`,`on` case‑insensitive). |
| C5 | Analyzer Settings | Analyzer DLL paths come from `.vscode/settings.json` (if present) keys `al.enableCodeAnalysis` and `al.codeAnalyzers`; invalid or missing file yields empty analyzer set without failure. |
| C6 | Analyzer Listing | `show-analyzers` prints discovered analyzers (or an explicit message when none) and exits 0. |
| C7 | Config Display | `show-config` emits a stable key/value list including at minimum `Platform`, `PowerShellVersion`, `RulesetStatus`, `WarningsAsErrors`. Missing optional inputs represented clearly (e.g., `RulesetStatus=Skipped`). |
| C8 | Compiler Discovery | Highest available AL compiler (VS Code AL extension) selected; absence produces a clear error and non‑zero exit (build abort). |
| C9 | Exit Code Mapping | Standard mapping (success=0, guard=2, analysis=3, contract=4, integration=5, missing tool=6, build/next-object-number domain exits e.g. range exhausted=2 already reserved, unexpected >6). |
| C10 | Output Paths | Output (`.app`) and package cache paths are deterministically derived; stale outputs are removed before build. |
| C11 | Next Object Number | Returns first free ID inside declared `idRanges`; exhaustion uses exit 2 (semantic reuse) with explanatory message; malformed `app.json` yields exit 1. |
| C12 | JSON Robustness | Malformed JSON in settings/app files causes guarded scripts to emit a clear error and exit non‑zero without partial execution. |
| C13 | Cross‑Platform Parity | Normalized output (whitespace & line endings) for core targets is identical across supported OSes. |
| C14 | Side-Effect Boundaries | No network calls; file system changes limited to build artifact and package cache directories. |

Rationale highlights:
* Silent ruleset skip (C3) avoids coupling success to optional quality configuration.
* Analyzer absence (C5/C6) is informative, not fatal, preserving build continuity.
* Exit code reuse for range exhaustion (C11) accepts minor semantic overload to keep mapping compact; documented clearly to avoid ambiguity.
* Deterministic derivation of output paths (C10) simplifies cleaning and idempotent rebuilds.

Traceability from Functional Requirements FR-001..FR-025 to Contracts C1–C14 is maintained in `contracts/README.md` and enforced by test matrix.

## Dependencies & Assumptions

- PowerShell 7.2+ installed on all supported hosts.
- GNU make available (`make --version` reports "GNU").
- Required modules pre-installed: PSScriptAnalyzer (min version to be documented), Pester ≥ 5.0.0.
- Git present if ancillary metadata retrieval is later required (not mandatory for core build path).
- No outbound network access required for normal operations or tests.
- File system supports UTF-8; scripts do not require elevated privileges.
- CI environments: GitHub Actions `windows-latest` and `ubuntu-latest` images assumed representative for consumers.
- Parallel invocations rely on process isolation; no shared mutable state.
