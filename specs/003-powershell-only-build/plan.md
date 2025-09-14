# Implementation Plan: PowerShell-Only Build Script Consolidation

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

## Summary
Consolidate build-related scripts to a single cross-platform PowerShell implementation guarded by a transient environment variable (`ALBT_VIA_MAKE`) to enforce invocation exclusively through `make`. Provide contract + integration Pester tests and a mandatory PSScriptAnalyzer quality gate. Achieve functional parity with existing Bash scripts, enabling their deprecation and later removal without user-visible regressions.

## Technical Context
**Languages**: PowerShell 7.2+ (single source for Windows & Linux)
**Entrypoints (guarded)**: `overlay/scripts/make/build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`
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

## Project Structure (Target Changes)
```
overlay/
  scripts/
    make/
      build.ps1
      clean.ps1
      show-config.ps1
      show-analyzers.ps1
      lib/
        Guard.ps1
        Common.ps1 (logging, verbosity, path helpers)
    next-object-number.ps1 (unchanged, unguarded)

.config/
  ScriptAnalyzerSettings.psd1

tests/
  contract/*.Tests.ps1
  integration/*.Tests.ps1
```

## Phase 0: Outline & Research (see research.md)
Focus: Evaluate guard enforcement patterns, PSSA rule selection, parallel invocation isolation, help strategy (stub vs full under guard), exit code mapping, required module presence detection. All unknowns resolved via Decisions in spec.

## Phase 1: Design & Contracts
Artifacts: `data-model.md` (conceptual entities, guard interaction), `contracts/README.md` (script behavior contracts + exit code table), `quickstart.md` (user workflow). No external API; internal CLI surface only.

## Phase 2: Task Planning Approach
Each functional requirement (FR-001..FR-025) maps to one or more tasks. Group tasks by phases: scaffolding, guard implementation, analysis gate, tests, CI, documentation, deprecation. `tasks.md` enumerates atomic actionable steps with acceptance criteria and references to FR IDs.

## Phase 3+: Implementation & Validation
Out of scope for this planning artifact; will execute tasks ensuring green PSSA + tests across matrix.

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
