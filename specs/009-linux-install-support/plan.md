# Implementation Plan: Linux Installation Support

**Branch**: `009-linux-install-support` | **Date**: 2025-10-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-linux-install-support/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable AL Build Tools installation on Ubuntu Linux systems with equivalent functionality to Windows installer. Primary requirement: Create bootstrap installer scripts for Linux that detect prerequisites (Git, PowerShell 7, .NET SDK, InvokeBuild), install missing tools via apt/Microsoft repos, download overlay, and enforce same git repository guards and diagnostic output as Windows. Technical approach: Create bash scripts for Linux installer (`bootstrap/install-linux.sh`, `bootstrap/install-prerequisites-linux.sh`) since PowerShell is a prerequisite that needs to be installed. Bash handles apt operations and git integration; delegates to PowerShell after installation for module setup. Add Docker-based test harness for Ubuntu containers and maintain Windows/Linux diagnostic output parity.

## Technical Context

**Language/Version**: Bash 4.x+ for bootstrap installer, PowerShell 7.2+ for overlay scripts (post-install)
**Primary Dependencies**: apt package manager, Microsoft PowerShell & .NET repositories, Docker for test containers
**Storage**: File system (overlay copy, cache directories ~/.bc-tool-cache, ~/.bc-symbol-cache)
**Testing**: Pester (PowerShell testing framework), Docker-based container tests, JSON artifact validation
**Target Platform**: Ubuntu Linux 22.04 LTS (x64/amd64 architecture)
**Project Type**: Bootstrap installer + test infrastructure (bash installer scripts + PowerShell overlay + CI validation)
**Performance Goals**: Complete installation in <5 minutes on typical network/hardware
**Constraints**: Bootstrap installer must be bash (PowerShell is a prerequisite); must preserve Windows/Linux parity for diagnostics, exit codes, guard behavior; auto-install mode for CI; interactive prompts for human users; sudo session caching (no credential prompts during install)
**Scale/Scope**: 10+ test scenarios covering fresh install, partial prerequisites, network failures, git guard violations; support Ubuntu 22.04 LTS initially

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Planned changes preserve the public `overlay/` contract and document any compatibility risk.
  - **Status**: PASS - This feature only adds Linux installer scripts to `bootstrap/` directory, does not modify existing overlay files. Overlay scripts already support cross-platform execution.
- [x] All overlay scripts remain self-contained and maintain Windows/Linux parity (justify any exceptions).
  - **Status**: PASS - No overlay script changes required. Existing overlay scripts (e.g., `download-compiler.ps1`) already contain Linux compatibility with platform detection.
- [x] Execution guard (`ALBT_VIA_MAKE`) and standard exit codes stay intact or include an approved migration plan.
  - **Status**: PASS - Linux installer will implement same guard pattern and exit code semantics (0=Success, 1=GeneralError, 2=Guard, 6=MissingTool) as Windows installer.
- [x] Tool provisioning stays deterministic and respects cache location conventions (`ALBT_*` environment overrides).
  - **Status**: PASS - Linux installer will provision prerequisites (Git, PowerShell 7, .NET SDK) and overlay download without altering overlay provisioning logic. Cache paths (`~/.bc-tool-cache`, `~/.bc-symbol-cache`) work cross-platform.
- [x] Release workflow keeps copy-only distribution and excludes internal maintenance assets from shipped artifacts.
  - **Status**: PASS - Linux installer scripts go into `bootstrap/` alongside existing `install.ps1`. Test harness goes into `scripts/ci/`. No changes to release packaging in `scripts/release/overlay.ps1`.

**Gate Result**: ✅ APPROVED - All constitution principles satisfied, no violations requiring justification.

## Project Structure

### Documentation (this feature)

```
specs/009-linux-install-support/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── installer-schema.json          # JSON schema for installer diagnostic output
│   ├── test-summary-schema.json       # JSON schema for test harness summary artifacts
│   └── exit-codes.md                  # Exit code reference for Linux installer
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# Bootstrap installer scripts (public contract)
bootstrap/
├── install.ps1                      # Existing Windows installer (PowerShell)
├── install-prerequisites.ps1        # Existing Windows prerequisites installer (PowerShell)
├── install-linux.sh                 # NEW: Linux installer (Bash - main entry point)
└── install-prerequisites-linux.sh   # NEW: Linux prerequisites installer (Bash - apt operations)

# Test infrastructure (internal maintenance)
scripts/ci/
├── test-bootstrap-install.ps1       # Existing Windows test harness (PowerShell)
├── test-bootstrap-install-linux.ps1 # NEW: Linux test harness (PowerShell - runs on host, provisions Docker)
├── container-test-overlay-provision.ps1
├── container-test-template.ps1
└── testdata/                        # Existing test scenarios reused for Linux

# Overlay (unchanged - already cross-platform compatible)
overlay/
├── al.build.ps1
├── scripts/
│   ├── common.psm1                  # Already cross-platform utilities
│   └── make/
│       ├── download-compiler.ps1    # Already Linux-compatible (requires PS7 installed)
│       ├── download-symbols.ps1     # Already Linux-compatible (requires PS7 installed)
│       └── ...
```

**Structure Decision**: Single project with bootstrap installer + test infrastructure. Linux installer scripts use bash (prerequisite-free) for bootstrap phase, then delegate to PowerShell after installation. Test harness remains PowerShell (runs on host machine with Docker). No overlay changes needed due to existing cross-platform design.

---

## Phase 0: Research & Technical Decisions

**Status**: ✅ COMPLETE
**Output**: `research.md`

### Key Decisions Made

1. **Ubuntu Package Management**: Use apt with Microsoft repositories for PowerShell 7 and .NET SDK
   - Git from default Ubuntu repos, PowerShell/dotnet from Microsoft apt repos
   - Add Microsoft repo: Download and install packages-microsoft-prod.deb
   - Alternative rejected: Snap packages (different path model, less suitable for automation)

2. **Sudo Privilege Escalation**: Expect cached sudo session (user runs `sudo -v` before installer)
   - Avoids credential prompts during install, CI-friendly
   - Clear error message when sudo unavailable (exit code 6)
   - Alternative rejected: Interactive prompts (breaks auto-install mode)

3. **Apt Lock Conflict Handling**: Retry with exponential backoff (5s, 10s, 20s), max 3 retries
   - Handles Ubuntu unattended-upgrades gracefully
   - ~35 seconds total wait balances patience vs timeout
   - Alternative rejected: Immediate failure (poor UX for temporary locks)

4. **Docker Test Harness**: Adapt Windows test harness pattern using ubuntu:22.04 base image
   - Proven pattern from `test-bootstrap-install.ps1`: provision → run → capture → summarize
   - Docker provides fast, ephemeral clean environments
   - Alternative rejected: VM-based testing (slower, heavier resource overhead)

5. **Diagnostic Output Parity**: Reuse exact Windows marker format
   - Same structured markers: `[install] prerequisite tool="git" status="check"`
   - Same exit codes: 0=Success, 2=Guard, 6=MissingTool
   - Enables cross-platform tooling and unified CI dashboards

6. **Interactive Prompt Validation**: Display error with example, retry once after 2s, then fail
   - Handles typos without annoying users
   - Prevents infinite loops if input broken
   - Alternative rejected: No retry (harsh penalty for single mistake)

7. **Bootstrap Installer Language**: Bash for installer, PowerShell for overlay (post-install)
   - **Critical**: PowerShell is a prerequisite, so installer must be bash to avoid circular dependency
   - Bash pre-installed on all Ubuntu systems
   - Matches Windows pattern: use pre-installed shell (Windows has PS 5.1, Linux has bash)
   - Alternative rejected: PowerShell installer (circular dependency - can't run PS if not installed)

8. **Overlay Integrity**: Test extraction after download (no SHA256 validation in v1)
   - Matches Windows installer behavior
   - Extraction test detects corrupt archives
   - Alternative rejected: SHA256 validation (adds release workflow complexity)

### All NEEDS CLARIFICATION Resolved

Technical Context section had no "NEEDS CLARIFICATION" markers. All unknowns from spec resolved through research:
- Sudo handling strategy (cached session)
- Apt lock conflicts (exponential backoff)
- Input validation (error + retry once)
- Archive integrity (extraction test)

**Research artifact**: See `research.md` for detailed rationale and implementation notes for each decision.

---

## Phase 1: Design & Contracts

**Status**: ✅ COMPLETE
**Output**: `data-model.md`, `contracts/`, `quickstart.md`

### Data Model

Created comprehensive entity model defining:
- **InstallerConfiguration**: Parameters and environment config
- **PrerequisiteTool**: Individual tool (git, powershell, dotnet, InvokeBuild) with status transitions
- **PrerequisiteSummary**: Aggregate of all prerequisite checks
- **InstallationPhase**: Timed execution phases (release-resolution, prerequisite-installation, etc.)
- **DiagnosticMarker**: Structured diagnostic output with type-specific fields
- **ReleaseMetadata**: GitHub release information
- **GitRepositoryState**: Repository validation state
- **InstallationSummary**: Top-level aggregate for test harness JSON output
- **TestScenario**: Docker test case configuration

### Contracts Generated

1. **exit-codes.md**: Exit code reference with Linux-specific scenarios
   - Documented all exit codes: 0 (success), 1 (general), 2 (guard), 6 (missing-tool)
   - Example outputs and common causes for each code
   - CI integration examples (bash, GitHub Actions)
   - Windows/Linux comparison table

2. **test-summary-schema.json**: JSON schema for test harness summary
   - metadata, prerequisites, phases, gitState, release, exitCode, diagnostics, success
   - Platform-specific fields (sudoCached for Linux)
   - Example JSON document
   - Validation rules for schema compliance

3. **installer-diagnostic-schema.json**: Schema for individual diagnostic markers
   - Type-specific schemas: prerequisite, step, guard, phase, diagnostic, input
   - Format pattern: `[install] <type> key="value"`
   - Real examples for each marker type

4. **contracts/README.md**: Contract documentation and usage guide
   - Explains each contract artifact
   - Cross-platform parity table
   - Validation examples
   - Contract evolution and versioning policy

### Quickstart Guide

Created `quickstart.md` with:
- **End User Instructions**: System prep, one-liner install, expected output
- **Developer Workflow**: Implementation phases, local testing, validation
- **Testing Scenarios**: Fresh install, partial prereqs, sudo issues, git guards
- **Diagnostic Examples**: Success case, failure case, guard violations
- **Troubleshooting**: Common issues and solutions

### Agent Context Updated

Ran `update-agent-context.ps1 -AgentType copilot` to update `.github/copilot-instructions.md`:
- Added language: PowerShell 7.2+ (cross-platform scripting)
- Added framework: apt package manager, Microsoft repos, Docker
- Added database: File system (cache directories)
- Context now reflects Linux-specific patterns for future development

---

## Phase 2: Task Breakdown

**Status**: ⏳ DEFERRED - Use `/speckit.tasks` command to generate `tasks.md`

Per workflow instructions, Phase 2 (task breakdown) is NOT created by `/speckit.plan` command. Run `/speckit.tasks` separately to generate implementation tasks with effort estimates, dependencies, and acceptance criteria.

---

## Post-Design Constitution Re-Check

*GATE: Re-evaluate constitution after Phase 1 design complete*

- [x] Planned changes preserve the public `overlay/` contract and document any compatibility risk.
  - **Re-check**: ✅ PASS - Design confirms no overlay changes. All new code in `bootstrap/` and `scripts/ci/`.

- [x] All overlay scripts remain self-contained and maintain Windows/Linux parity (justify any exceptions).
  - **Re-check**: ✅ PASS - No overlay script modifications. Existing scripts already cross-platform.

- [x] Execution guard (`ALBT_VIA_MAKE`) and standard exit codes stay intact or include an approved migration plan.
  - **Re-check**: ✅ PASS - Linux installer implements identical guard pattern and exit code contract documented in `contracts/exit-codes.md`.

- [x] Tool provisioning stays deterministic and respects cache location conventions (`ALBT_*` environment overrides).
  - **Re-check**: ✅ PASS - Linux prerequisite installer uses apt for system packages, respects cache paths (`~/.bc-tool-cache`, `~/.bc-symbol-cache`), deterministic overlay download.

- [x] Release workflow keeps copy-only distribution and excludes internal maintenance assets from shipped artifacts.
  - **Re-check**: ✅ PASS - Bootstrap scripts added to public distribution (`bootstrap/install-linux.ps1`, `bootstrap/install-prerequisites-linux.ps1`). Test harness stays in `scripts/ci/` (internal). No release workflow changes needed.

**Gate Result**: ✅ APPROVED - Design maintains full constitution compliance, ready for implementation.

---

## Summary & Next Steps

### Completed

- ✅ **Constitution Check**: All principles satisfied, no violations
- ✅ **Phase 0 Research**: 8 technical decisions documented with rationale
- ✅ **Phase 1 Design**: Data model, contracts (4 artifacts), quickstart guide created
- ✅ **Agent Context**: Updated Copilot instructions with new technology stack
- ✅ **Post-Design Re-Check**: Constitution compliance confirmed

### Artifacts Generated

```
specs/009-linux-install-support/
├── plan.md                          ✅ This file
├── research.md                      ✅ Technical decisions
├── data-model.md                    ✅ Entity model
├── quickstart.md                    ✅ Getting started guide
└── contracts/
    ├── README.md                    ✅ Contract overview
    ├── exit-codes.md                ✅ Exit code reference
    ├── test-summary-schema.json     ✅ Test harness schema
    └── installer-diagnostic-schema.json ✅ Diagnostic marker schema
```

### Next Steps

1. **Run `/speckit.tasks`** to generate `tasks.md` with implementation task breakdown
2. **Implement** `bootstrap/install-linux.ps1` (main Linux installer)
3. **Implement** `bootstrap/install-prerequisites-linux.ps1` (apt-based prereq installer)
4. **Implement** `scripts/ci/test-bootstrap-install-linux.ps1` (Docker test harness)
5. **Test** across scenarios (fresh install, partial prereqs, failures)
6. **Validate** JSON output against schemas
7. **Document** in README and release notes
8. **Release** with announcement of Linux support

---

**Planning Phase**: ✅ COMPLETE - Ready for task breakdown and implementation

