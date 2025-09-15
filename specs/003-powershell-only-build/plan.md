# Implementation Plan: PowerShell-Only Build Script Consolidation (Relocation & Reuse)

**Branch**: `003-powershell-only-build` | **Date**: 2025-09-14 | **Spec**: `d:/repos/al-build-tools/specs/003-powershell-only-build/spec.md`
**Input**: Feature specification from `/specs/003-powershell-only-build/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type (single tooling repo)
   → Set Structure Decision (retain single project layout)
3. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
4. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
5. Execute Phase 1 → contracts, data-model.md, quickstart.md
6. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
7. Plan Phase 2 → Describe task generation approach (DO create tasks.md in this feature flow per repository planning prompt)
8. STOP - Ready for implementation
```

**IMPORTANT**: This feature's planning includes generating `tasks.md` (Phase 2) to accelerate implementation (repository prompt adaptation). Implementation & validation follow after plan artifacts.

## Summary (Updated)
This plan no longer creates net‑new PowerShell scripts; instead it RELOCATES the already functional Windows PowerShell scripts (`overlay/scripts/make/windows/*.ps1`) into the neutral `overlay/scripts/make/` directory, DELETES all Bash scripts under `overlay/scripts/make/linux/`, and ENHANCES the relocated scripts (guard, verbosity normalization, deterministic config output, standardized exit codes). We preserve proven logic, reducing risk versus rewrite while achieving a single cross‑platform surface. Parity with prior Windows behavior and replacement of Bash scripts are validated through contract & integration tests.

Contracts C1–C14 still define authoritative externally observable behavior. Relocation adds a new implicit objective: baseline parity (FR-025) between pre‑relocation Windows outputs and post‑relocation unified scripts.

## Technical Context
**Languages**: PowerShell 7.2+ (single source for Windows & Linux)
**Entrypoints (guarded, after relocation)**: `overlay/scripts/make/build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1` (moved from windows/ subfolder)
**Removed**: All Bash scripts previously in `overlay/scripts/make/linux/`
**Direct Tool (unguarded)**: `overlay/scripts/next-object-number.ps1`
**Guard Variable**: `ALBT_VIA_MAKE` (process-scoped, must not persist)
**Static Analysis**: PSScriptAnalyzer (Recommended + selected style rules via `.config/ScriptAnalyzerSettings.psd1`)
**Testing Framework**: Pester v5 (contract + integration)
**CI**: GitHub Actions matrix (`ubuntu-latest`, `windows-latest`), order: PSSA → Contract tests → Integration tests → Publish results
**Exit Codes**: 0 success, 2 guard violation, 3 static analysis failure, 4 contract test failure, 5 integration failure, 6 missing required tooling, >6 unexpected.
**Non-Goals**: Modify analyzers, bundling binaries, changing bootstrap UX beyond doc updates.

## Constitution Check
Simplicity: Single scripting language; removes duplicated Bash logic.
Architecture: No new runtime dependencies besides existing PowerShell & PSScriptAnalyzer/Pester.
Testing: Contract first, then integration; hermetic with TestDrive.
Observability: Verbose mode unified; minimal additional logging.
Versioning: No outward behavioral change except enforced invocation path; documented.
Result: PASS (initial). Re-check after Phase 1 expected PASS.

## Project Structure (Target End State)
```
overlay/
   scripts/
      make/
         build.ps1              # relocated from windows/, now guarded & cross-platform
         clean.ps1              # relocated
         show-config.ps1        # relocated
         show-analyzers.ps1     # relocated
      next-object-number.ps1   # unchanged (unguarded)

# Removed in this feature: overlay/scripts/make/linux/* (all Bash)
# Removed after relocation: overlay/scripts/make/windows/ (folder deleted once scripts moved)

# Internal only (not shipped)
.config/ScriptAnalyzerSettings.psd1
tests/contract/*.Tests.ps1
tests/integration/*.Tests.ps1
tests/helpers/*.ps1 (normalization, spawn, optional)
```

Inline Implementation Notes:
- Guard logic: a few lines at top of each guarded script; no shared overlay module required.
- Exit codes: documented as a comment table + `switch` usage inside scripts; central constant file kept internal only if needed for tests.
- Tool detection & static analysis: performed in CI (repository context). Consumers do not receive these helper functions—scripts fail fast only on guard violations in normal use.
- Duplication threshold: if any shared logic grows beyond ~20 lines duplicated across ≥3 scripts, reconsider introducing a single small shared helper (but only if clearly justified and still minimal for consumers).

## Phase 0: Outline & Research (Completed)
Focus remains valid; added confirmation that existing Windows scripts are suitable for direct relocation with minimal path normalization.

## Phase 1: Design & Contracts (Adjusted)
Artifacts updated to replace "create new scripts" language with "relocate & enhance". Contracts unchanged; add parity note referencing FR-025.

## Phase 2: Task Planning Approach (Adjusted)
Task list revised to: (a) Inventory existing Windows scripts, (b) Relocate & inline helpers, (c) Delete Bash & windows folders, (d) Add guard + enhancements, (e) Establish parity baselines, (f) Implement tests, (g) Update Makefile & docs, (h) CI adjustments.
`tasks.md` will be rewritten to drop greenfield scaffold tasks and replace them with relocation + enhancement steps.

## Phase 3+: Implementation & Validation
Execute relocation first (copy then delete) in a single commit set to avoid a transient broken state. Follow with enhancements and parity verification tests prior to final Bash removal commit if staged. PSSA + Pester green required before merging.

## Complexity Tracking
No deviations; table empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|---------------------------------------|

## Progress Tracking
**Phase Status**:
- [x] Phase 0: Research complete
- [x] Phase 1: Design complete
- [x] Phase 2: Task planning complete
- [ ] Phase 3: Implementation complete
- [ ] Phase 4: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [ ] Complexity deviations documented (none required)

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*
