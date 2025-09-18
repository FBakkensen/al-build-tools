# Implementation Plan: Release-Based Installer

**Branch**: `007-description-i-want` | **Date**: 2025-09-18 | **Spec**: `/home/fbakkensen/repos/al-build-tools/specs/007-description-i-want/spec.md`
**Input**: Feature specification from `/specs/007-description-i-want/spec.md`

## Summary
Shift `bootstrap/install.ps1` from branch archive downloads to release asset retrieval while preserving guard semantics. The installer will resolve the effective release tag (favoring `-Ref`, then `ALBT_RELEASE`, then latest published release), normalize tag formats, fetch the `overlay.zip` asset via the GitHub Releases API, and surface the resolved tag in diagnostics. README and CHANGELOG updates will document the new selection logic.

## Technical Context
**Language/Version**: PowerShell 7.0+
**Primary Dependencies**: GitHub REST API (releases), `Invoke-WebRequest`
**Storage**: N/A (transient temp directories only)
**Testing**: Existing PowerShell Pester contract tests; add new coverage for release resolution if needed
**Target Platform**: Cross-platform (PowerShell Core on Windows/Linux)
**Project Type**: single
**Performance Goals**: Maintain current install runtime characteristics (<10s typical)
**Constraints**: Unauthenticated GitHub API limit (60 req/hour), no persistent state, maintain guard exit codes
**Scale/Scope**: Single script change plus docs; no overlay payload modifications required

## Constitution Check
- **Cross-Platform Parity**: Installer logic remains within PowerShell and preserves stdout contract; Linux/Windows behavior identical.
- **Repeatable Operations**: Release asset downloads remain idempotent; re-running yields identical overlay copy.
- **Workspace Purity**: Only touches provided destination; selection based on explicit parameters/env vars.
- **Transparent Contracts**: Success diagnostic extends message but retains existing format; guard classifications unchanged.
- **Overlay Minimalism**: No new overlay files introduced; installer continues to distribute current payload.

Gate result: PASS (no violations detected).

## Project Structure
```
specs/007-description-i-want/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── install-diagnostics.md
└── spec.md
```

**Structure Decision**: Option 1 (single project) — no repository restructuring needed.

## Phase 0: Outline & Research
- Resolved API usage, asset download strategy, tag normalization, diagnostics, and env precedence questions (see `/home/fbakkensen/repos/al-build-tools/specs/007-description-i-want/research.md`).
- Outstanding verification items captured: ensure release automation produces `overlay.zip`; confirm GitHub rate limits acceptable for automation scenarios.
- All NEEDS CLARIFICATION addressed or tracked for validation.

## Phase 1: Design & Contracts
- Identify transient entities required for release selection (see `/home/fbakkensen/repos/al-build-tools/specs/007-description-i-want/data-model.md`).
- Document installer diagnostic expectations and failure behaviors (see `/home/fbakkensen/repos/al-build-tools/specs/007-description-i-want/contracts/install-diagnostics.md`).
- Quickstart outlines cross-platform validation steps for success, env override, normalization, and NotFound scenarios (see `/home/fbakkensen/repos/al-build-tools/specs/007-description-i-want/quickstart.md`).
- No agent context update required at this stage; existing guidance remains accurate.

## Phase 2: Task Planning Approach
- Update `bootstrap/install.ps1` to resolve release metadata, normalize tag inputs, and download the selected asset.
- Introduce helper functions for API calls while keeping script self-contained.
- Extend diagnostics to include resolved tag and asset name without breaking current consumers.
- Refresh README and CHANGELOG with release-driven install instructions and precedence rules.
- Add or adjust tests to cover release selection paths (likely via PowerShell unit/contract tests using mocked HTTP responses).
- Validate NotFound and CorruptArchive guards against new code paths.

## Complexity Tracking
| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _None_ | | |

## Progress Tracking
**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented (N/A)

---
*Based on Constitution v1.1.0 - See `/home/fbakkensen/repos/al-build-tools/.specify/memory/constitution.md`*
