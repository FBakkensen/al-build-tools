<!-- Sync Impact Report
Version change: 0.0.0 → 1.0.0
Modified principles: (initial publication)
Added sections: Core Principles, Operational Constraints, Workflow & Quality Gates, Governance
Removed sections: None
Templates requiring updates:
- ✅ .specify/templates/plan-template.md
- ✅ .specify/templates/spec-template.md
- ✅ .specify/templates/tasks-template.md
- ✅ .specify/memory/constitution_update_checklist.md
Follow-up TODOs: None
-->

# AL Build Tools Constitution

## Core Principles

### Overlay Is The Product
- All files shipped under `overlay/` constitute the public contract. Changes MUST preserve consumer compatibility or include an explicit migration strategy approved in planning.
- Overlay content MUST remain copy-only: no hidden installers, service hooks, or dependencies that are not also copied to the consuming repository.
- Rationale: Treating `overlay/` as the deliverable keeps downstream repositories stable and predictable.

### Self-Contained Cross-Platform Scripts
- Overlay scripts MUST execute with only the prerequisites documented in the README (PowerShell 7.2+, .NET SDK, InvokeBuild) and may not import repo-internal modules.
- Windows and Linux variants of paired scripts MUST remain functionally equivalent. Any intentional divergence MUST be documented in specs and plans before merge.
- Rationale: Consumers rely on deterministic automation across host platforms; parity prevents release regressions.

### Guarded Execution & Exit Codes
- Entry points MUST respect the `ALBT_VIA_MAKE` guard. Direct invocation without the guard MUST fail with exit code 2 and a clear message.
- Scripts MUST return standardized exit codes (0 success, 1 general error, 2 guard, 3 analysis, 4 contract, 5 integration, 6 missing tool) and avoid silent failure paths.
- Rationale: The guard ensures scripts run through supported workflows and consistent exit codes keep CI diagnostics actionable.

### Deterministic Provisioning & Cache Hygiene
- Compiler provisioning MUST install the latest Microsoft AL compiler release available at run time (backward compatible by policy) unless an explicit override (`AL_TOOL_VERSION`, `ALBT_ALC_PATH`, or release pin) is supplied; symbol provisioning MUST still honor project configuration and record cache metadata under the documented sentinel locations.
- Tests and automation MUST start from clean state assumptions; provisioning steps MUST recreate required tools and symbols without relying on untracked host state.
- Rationale: Reproducible installs allow containerized and CI builds to match local behavior while leveraging Microsoft's backward-compatible compiler cadence.

### Copy-Only Release Discipline
- Releases MUST package only the `overlay/` directory (plus bootstrap installer) and MUST not include internal maintenance scripts, credentials, or experimental artifacts.
- Every release MUST document semantic version increments and include a successful dry run of the installer on a clean environment.
- Rationale: Copy-only updates keep adoption safe and version discipline signals compatibility expectations.

## Operational Constraints

- No secrets, tokens, or undocumented network calls may be introduced within overlay scripts. Allow-listed endpoints are limited to official Microsoft feeds used for tooling.
- Scripts MUST surface verbose logging behind `Write-Verbose` and avoid altering host-global state beyond documented cache directories.
- Configuration overrides MUST leverage the `ALBT_*` environment variables and may not hard-code user-specific paths.
- Containers, build agents, and local runs MUST clean up temporary artifacts to avoid cross-run contamination.

## Workflow & Quality Gates

- All changes to overlay or bootstrap scripts MUST be accompanied by a feature spec and implementation plan referencing this constitution.
- PSScriptAnalyzer MUST run cleanly across `overlay/` and `bootstrap/install.ps1` before merge. Blocking findings require fixes rather than suppressions.
- Features impacting guarded execution, provisioning, or release flow MUST include automated validation (CI job, container test, or documented manual dry run) before tagging a release.
- Documentation (README, CLAUDE.md, release notes) MUST be updated whenever command surfaces, prerequisites, or workflows change.

## Governance

- This constitution supersedes other process documents when conflicts arise. All planning and review checklists MUST reference the principles above.
- Amendments require consensus from maintainers plus an updated spec-kit checklist showing template alignment. Material changes MUST follow semantic versioning: major for incompatible governance shifts, minor for new principles/sections, patch for clarifications.
- Ratification occurs on first publication. Each amendment MUST update `Last Amended`, document version changes in release notes or changelog, and ensure dependent templates remain synchronized.
- Compliance reviews occur during `/speckit.plan` and PR review. Violations MUST be resolved or explicitly deferred with risk owners before merge.

**Version**: 1.0.0 | **Ratified**: 2025-10-16 | **Last Amended**: 2025-10-16
