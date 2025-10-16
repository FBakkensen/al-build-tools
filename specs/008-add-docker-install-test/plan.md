# Implementation Plan: Docker-Based Install Script Test

**Branch**: `008-add-docker-install-test` | **Date**: 2025-10-16 | **Spec**: `specs/008-add-docker-install-test/spec.md`
**Input**: Feature specification from `/specs/008-add-docker-install-test/spec.md`

**Note**: Generated/maintained via `/speckit.plan` workflow.

## Summary

Automate an end-to-end validation of `bootstrap/install.ps1` inside a clean Windows Docker container (Server Core LTSC 2022) to ensure each release ships with a working installer. The harness provisions an ephemeral container, installs PowerShell 7.2+ if missing, downloads the latest release artifact, executes the installer exactly like a first‑time consumer, captures transcripts and key artifacts, and surfaces success/failure (with diagnostics) both in CI and for local reproducibility.

## Technical Context

**Language/Version**: PowerShell (may start under Windows PowerShell 5.1; installer self-installs PowerShell 7.2+), Docker Windows containers (Server Core LTSC 2022)
**Primary Dependencies**: Docker (Windows), PowerShell, Git (for optional validation), Invoke-WebRequest (built-in), Expand-Archive, Release asset download (GitHub), existing `bootstrap/install.ps1`
**Storage**: N/A (ephemeral container filesystem only; artifacts exported to host/CI workspace)
**Testing**: Exit code + log inspection (Pester optional future) – MVP avoids extra dependency
**Target Platform**: Windows Server Core (container) running on a Windows host with Windows container support
**Project Type**: Test harness (planned future PowerShell script under `scripts/ci/` plus thin GitHub Actions workflow) – DECIDED (no code implemented during planning phase)
**Performance Goals**: Complete baseline successful install within 20 minutes (SC-001); stretch goal < 10 minutes typical
**Constraints**: Must not modify public overlay contract; must avoid persisting host caches; network-only access to GitHub releases; minimal base image footprint; deterministic reproducibility
**Scale/Scope**: Single container per test execution; no parallel orchestration required initially

UNKNOWNS / NEEDS CLARIFICATION: (All resolved in research; none open for Phase 0/1 planning.)

Resolved Decisions Summary (see research.md for rationale):
- Harness delivered as future `scripts/ci/test-bootstrap-install.ps1`; workflow only invokes it.
- MVP relies on exit code + transcripts (Pester deferred).
- Select latest published release by default; override via env.
- PowerShell 7.2+ installed by installer if absent (container intentionally starts with Windows PowerShell 5.1).
- Use Invoke-WebRequest for asset retrieval (no GitHub CLI dependency).
- Artifacts exported to `out/test-install/` and uploaded as `installer-test-logs`.

Local/CI Parity Commitment: The GitHub Actions workflow MUST perform no logic beyond calling the harness script and uploading artifacts; all environment preparation (including PowerShell upgrade inside container) lives in installer and harness script to guarantee identical local reproduction.

## Constitution Check

*GATE (Pre-Research)*

- [x] Planned changes preserve the public `overlay/` contract (no modification to shipped script behavior; adds only test harness outside `overlay/`).
- [x] All overlay scripts remain self-contained and maintain Windows/Linux parity (no overlay changes yet; container test is Windows-only but justified as installer bootstrap validation requiring Windows base for Server Core—documented exception will be added if Linux parity not applicable for bootstrap script which is PowerShell cross-platform; NEEDS CLARIFICATION if Linux container test is desired later).
- [x] Execution guard (`ALBT_VIA_MAKE`) untouched (harness invokes only the bootstrap installer which is outside guarded overlay make scripts).
- [x] Tool provisioning remains deterministic; container starts clean each run; caches not reused.
- [x] Release workflow remains copy-only; harness not packaged inside release.

Gate Status (Pre-Research): PASS (pending resolution of listed UNKNOWNS in research phase).

Post-Design Re-Evaluation (after research & design artifacts): All unknowns resolved in `research.md`. Windows-only scope documented as intentional, not a violation (overlay parity unaffected since no overlay change). No constitutional violations introduced. Gate Status: PASS.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->



**Structure Decision**: No new production source directories; add (a) CI harness script `scripts/ci/test-bootstrap-install.ps1` (proposed) and (b) GitHub Actions workflow `.github/workflows/test-bootstrap-install.yml`. Documentation artifacts reside under existing `specs/008-add-docker-install-test/` directory. No impact to overlay/.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Windows-only test harness | Installer bootstrap target is Windows-specific environment validation first; Linux adds no immediate coverage for Windows container provisioning | Building multi-platform harness now adds complexity & time; can iterate later |
| Added CI script outside overlay | Keep overlay contract minimal; tests should not ship | Embedding logic into overlay would bloat public surface |

## Phase 0 Research Plan (Auto-Generated Placeholder)

Will extract and resolve UNKNOWNS into `research.md` with decisions, rationale, and alternatives.

## Phase 1 Design Placeholder

Will generate `data-model.md`, `contracts/`, and `quickstart.md` after research completion.

## Phase 2 Tasks Placeholder

Tasks will be generated by `/speckit.tasks` (out of scope for current command).

