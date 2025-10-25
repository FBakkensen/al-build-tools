# Feature Specification: Linux Installation Support

## Overview

Enable AL Build Tools installation on Ubuntu Linux systems with the same user experience, diagnostic capabilities, and testing rigor as the existing Windows installation. Users working in Linux development environments should have a first-class installation experience that mirrors Windows functionality.

## Clarifications

### Session 2025-10-25

- Q: How should installer handle sudo password in auto-install mode? → A: Expect cached sudo session (user runs `sudo -v` before installer, fails gracefully if expired)
- Q: Should installer mask/redact credentials in logs and diagnostic output? → A: No masking, log everything for maximum transparency and debugging capability
- Q: What should installer do when apt is locked by another process? → A: Wait with exponential backoff (5s, 10s, 20s), max 3 retries, then fail with diagnostic
- Q: What happens when user provides invalid input to interactive prompts? → A: Show error with example, retry with 2s delay once, then fail gracefully if still invalid
- Q: How should installer validate overlay file integrity after download? → A: Test archive extraction only, matching current Windows installer behavior

## User Scenarios & Testing

### User Story 1 - Fresh Installation on Ubuntu System (Priority: P1)

A developer working on an Ubuntu workstation or server wants to install AL Build Tools into their git repository to enable Business Central AL development workflows. They should be able to run a single installer command that handles all prerequisites and overlay installation automatically.

**Why this priority**: Core installation capability is the foundation - without this, no other Linux features matter. Delivers immediate value by enabling Linux users to adopt the toolset.

**Independent Test**: Run installer on clean Ubuntu system with git repository, verify overlay files present and build system functional.

**Acceptance Scenarios**:

1. **Given** a clean Ubuntu system with no prerequisites installed and a git repository, **When** user runs the installer with auto-install mode enabled, **Then** installer detects missing prerequisites, installs them via package manager, downloads overlay, copies files to destination, stages and commits changes, and reports success with diagnostic markers
2. **Given** an Ubuntu system with all prerequisites already installed, **When** user runs the installer, **Then** installer detects existing tools, skips installation steps, proceeds directly to overlay download and copy, and completes successfully
3. **Given** an Ubuntu system with partial prerequisites (e.g., git installed but not PowerShell 7), **When** user runs the installer, **Then** installer identifies missing tools, installs only what's needed, and continues installation

---

### User Story 2 - Interactive Prerequisite Installation (Priority: P2)

A developer unfamiliar with PowerShell or AL Build Tools runs the installer on their Ubuntu system. When prerequisites are missing, they should receive clear prompts explaining what will be installed and why, with the option to proceed or cancel.

**Why this priority**: User confidence and transparency during installation builds trust. While auto-install mode handles CI/container scenarios, interactive mode serves human users who want control.

**Independent Test**: Run installer without auto-install mode, verify interactive prompts appear for missing prerequisites, user can approve/decline each tool.

**Acceptance Scenarios**:

1. **Given** an Ubuntu system missing PowerShell 7 and user runs installer in interactive mode, **When** prerequisite check runs, **Then** installer displays message explaining PowerShell 7 requirement and purpose, prompts for confirmation, and proceeds only if user approves
2. **Given** an Ubuntu system with non-standard package manager state (e.g., apt cache out of date), **When** prerequisite installation begins, **Then** installer updates package cache transparently and reports progress
3. **Given** a user who declines prerequisite installation, **When** prompted, **Then** installer exits gracefully with clear message about missing requirements and how to install manually

---

### User Story 3 - Docker-Based Installation Testing (Priority: P3)

A maintainer or CI system needs to validate that the Linux installer works correctly across clean Ubuntu installations, prerequisite scenarios, and failure modes. Testing should run in ephemeral Docker containers that mirror real-world installation conditions.

**Why this priority**: Automated testing ensures installation reliability and prevents regressions. Critical for maintaining Windows/Linux parity and release quality.

**Independent Test**: Execute test harness with Ubuntu container, verify installer runs to completion, overlay files present, artifacts generated with expected schema.

**Acceptance Scenarios**:

1. **Given** a test harness pointing to a specific release tag, **When** test runs in Ubuntu container, **Then** container provisions cleanly, installer downloads correct overlay version, installation succeeds, and summary JSON artifacts are generated with execution timing and tool status
2. **Given** a test scenario simulating network failure, **When** installer attempts to download overlay, **Then** container captures diagnostic output, failure is logged with category and hint, and exit code reflects network error condition
3. **Given** a test scenario with git repository missing, **When** installer runs prerequisite checks, **Then** guard condition is triggered, diagnostic marker emitted, and installer exits with guard exit code

---

### User Story 4 - Diagnostic and Error Reporting Parity (Priority: P4)

A developer or CI system analyzing installer failures needs consistent diagnostic output across Windows and Linux platforms. Error messages, exit codes, and structured diagnostic markers should follow the same patterns regardless of platform.

**Why this priority**: Platform-consistent diagnostics enable unified tooling, documentation, and support workflows. Lower priority because core installation (P1-P3) must work first.

**Independent Test**: Compare diagnostic output from Windows and Linux installers across equivalent scenarios, verify marker format and exit codes match.

**Acceptance Scenarios**:

1. **Given** installer running on Linux encounters missing git repository, **When** guard check executes, **Then** diagnostic output includes `[install] guard GitRepoRequired` marker matching Windows format
2. **Given** installer running on Linux with clean working tree violated, **When** check executes, **Then** diagnostic output includes working tree status details and exits with same code as Windows
3. **Given** installer completing successfully on Linux, **When** execution finishes, **Then** structured output includes step markers with index and name matching Windows pattern

---

### Edge Cases

- What happens when apt package manager is locked by another process (answer: installer retries with exponential backoff - 5s, 10s, 20s delays - up to 3 times, then fails with diagnostic message)?
- How does installer handle systems with custom PowerShell 7 installation paths or snap packages (answer: installer only detects PowerShell in system PATH via `command -v pwsh`; users with custom installations should add pwsh to PATH or use symlink before running installer)?
- What happens when user lacks sudo privileges or sudo session is expired (answer: installer exits with MissingTool code and diagnostic message directing user to run `sudo -v` first)?
- How does installer behave when Microsoft package repositories are unreachable but apt repositories are available (answer: installer fails with GeneralError exit code and diagnostic message about Microsoft repo connectivity; user must resolve network/repo issue before retrying)?
- What happens when overlay download succeeds but extraction fails due to disk space (answer: extraction failure triggers GeneralError with diagnostic hint to check available disk space)?
- How does installer handle git repositories with non-standard configurations (e.g., worktrees, submodules) (answer: installer performs standard `git status --porcelain` check regardless of repo configuration; worktrees and submodules work as long as working tree is clean)?
- What happens when auto-install mode is used in a non-interactive SSH session without TTY (answer: relies on cached sudo session, no interactive prompts needed)?

## Requirements

### Functional Requirements

- **FR-001**: Installer MUST provide equivalent functionality on Ubuntu Linux as Windows installer, including prerequisite detection, overlay download, file copy, and git integration
- **FR-002**: Installer MUST detect presence of required prerequisites (Git, PowerShell 7, .NET SDK, InvokeBuild module) on Ubuntu systems using platform-appropriate detection methods
- **FR-003**: Installer MUST install missing prerequisites via apt package manager for system packages (Git) and Microsoft package repositories for PowerShell 7 and .NET SDK
- **FR-004**: Installer MUST support auto-install mode (via ALBT_AUTO_INSTALL environment variable) for non-interactive execution in CI and container environments
- **FR-005**: Installer MUST emit standardized diagnostic markers (e.g., `[install] prerequisite tool="git" status="check"`) matching Windows installer format
- **FR-006**: Installer MUST enforce git repository requirement and clean working tree before overlay copy, using same guard diagnostics as Windows
- **FR-007**: Installer MUST support release tag resolution via parameter (-Ref) or environment variable (ALBT_RELEASE), with fallback to latest non-draft release
- **FR-008**: Installer MUST validate overlay file integrity after download by testing archive extraction (matching Windows installer behavior); extraction failure indicates corrupt archive and MUST trigger diagnostic message with CorruptArchive category
- **FR-009**: Installer MUST create initial git commit for new repositories and stage/commit overlay files in existing repositories
- **FR-010**: Installer MUST reject unsupported parameters with usage guard message and exit code 2
- **FR-011**: Test harness MUST provision Ubuntu containers, execute installer, capture output, and generate JSON summary artifacts matching Windows test schema
- **FR-012**: Test harness MUST support configurable Ubuntu base images via environment variable for testing across Ubuntu LTS versions
- **FR-013**: Test harness MUST extract and report prerequisite installation status, step progression, and timing phases from container output
- **FR-014**: Installer MUST handle privilege escalation (sudo) by expecting a cached sudo session; users should run `sudo -v` before installer to cache credentials; installer MUST fail gracefully with MissingTool exit code and clear diagnostic message if sudo session is expired or unavailable
- **FR-015**: Installer MUST update apt package cache before prerequisite installation to ensure current package versions
- **FR-016**: Installer MUST validate apt package availability before attempting installation and provide meaningful error messages if packages are unavailable
- **FR-017**: Installer MUST handle apt lock conflicts (e.g., from unattended-upgrades) by retrying with exponential backoff (5s, 10s, 20s delays) up to 3 times before failing with diagnostic message
- **FR-018**: Installer MUST detect bash version 4.0+ before execution and fail gracefully with diagnostic message if running on incompatible shell version
- **FR-019**: Installer MUST handle invalid input in interactive prompts by displaying error message with valid input example, retrying once after 2s delay, then failing gracefully with GeneralError if still invalid
- **FR-020**: Installer MUST respect same exit code semantics as Windows: 0=Success, 1=GeneralError, 2=Guard, 6=MissingTool
- **FR-021**: Installer MUST log all diagnostic output without credential masking or redaction to maximize transparency and debugging capability; users are responsible for sanitizing logs before sharing
- **FR-022**: Test harness MUST generate provision.log capturing container setup output separately from installation transcript
- **FR-023**: Test harness MUST validate JSON summary schema compliance, including metadata, prerequisites, phases, and diagnostics sections

### Key Entities

- **Linux Installer Script** (`bootstrap/install-linux.sh`): Bootstrap bash script for Ubuntu systems, equivalent to install.ps1, handling parameter parsing, prerequisite orchestration, overlay download, and git integration
- **Linux Prerequisites Script** (`bootstrap/install-prerequisites-linux.sh`): Prerequisite installer bash script for Ubuntu, equivalent to install-prerequisites.ps1, managing apt packages and Microsoft repository configuration
- **Linux Test Harness** (`scripts/ci/test-bootstrap-install-linux.ps1`): Docker-based test infrastructure PowerShell script for Ubuntu containers, equivalent to test-bootstrap-install.ps1, validating installer behavior in clean environments
- **Ubuntu Container**: Ephemeral Docker container running Ubuntu LTS, providing clean test environment for installation validation
- **Installation Summary**: JSON artifact capturing execution metadata, prerequisite status, phase timing, and diagnostic output for analysis and debugging

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can complete AL Build Tools installation on Ubuntu system from single command execution in under 5 minutes (network: ≥10Mbps, hardware: ≥2 CPU cores, ≥4GB RAM, ≥1GB free disk space)
- **SC-002**: Installer successfully detects and installs all prerequisites (Git, PowerShell 7, .NET SDK, InvokeBuild) without user intervention in auto-install mode
- **SC-003**: Test harness successfully validates installer behavior across 10+ test scenarios (clean install, partial prerequisites, various failure modes) with 100% pass rate
- **SC-004**: Diagnostic output from Linux installer matches Windows installer format with 95%+ marker pattern consistency (exact `[install] <type> key="value"` format, all required fields present, field values in documented format) for cross-platform tooling compatibility
- **SC-005**: Installer handles prerequisite installation failures gracefully, providing actionable error messages in 100% of test scenarios
- **SC-006**: Installation completes successfully on Ubuntu 22.04 LTS in 95% of clean environment test runs
- **SC-007**: Test harness generates valid JSON summary artifacts conforming to schema in 100% of test executions
- **SC-008** (Aspirational): Users report successful installation on Ubuntu systems without manual intervention in 90% of support cases tracked after release

## Assumptions

- Users have sudo privileges on Ubuntu systems and can establish cached sudo session via `sudo -v` before running installer
- Ubuntu systems have internet connectivity to access apt repositories and Microsoft package sources
- Users are installing into git repositories they have write access to
- Docker is available for running test harness on Ubuntu hosts
- Ubuntu 22.04 LTS is the primary target with testing across LTS versions
- apt package manager is the standard package manager (not snap-only systems)
- PowerShell 7.2+ is compatible with Ubuntu LTS versions
- Microsoft package repositories for PowerShell and .NET SDK are publicly accessible
- Users accept default git configuration (user.name/user.email) in auto-install mode or can provide interactively

## Out of Scope

- Support for non-Ubuntu Linux distributions (Debian, RHEL, Fedora, Arch, etc.)
- Support for Ubuntu versions older than 20.04 LTS
- ARM architecture support (focus on x64/amd64 initially)
- GUI-based installation workflows
- Snap package installation methods
- Custom package manager configurations or third-party repositories
- Offline installation scenarios without internet access
- Windows Subsystem for Linux (WSL) specific optimizations
- Multi-user system-wide installations (focus on per-user installations)

## Dependencies

- Existing Windows installer scripts (install.ps1, install-prerequisites.ps1) serve as reference implementation for behavior and diagnostics
- Existing Windows test harness (test-bootstrap-install.ps1) provides schema and pattern for Linux test implementation
- GitHub Releases infrastructure for overlay.zip distribution remains unchanged
- Overlay contract and file structure defined in overlay/ directory applies equally to Linux installations
- Exit code semantics and guard patterns defined in common.psm1 and constitution must be preserved
- JSON summary schema used by Windows test harness must be compatible with Linux test harness output

## Notes

- This specification focuses on Ubuntu Linux support only as explicitly requested; future expansion to other distributions would require separate specification
- Windows/Linux parity is critical for overlay scripts and diagnostics but installation methods naturally differ due to platform package managers
- Test harness must validate same installation contract regardless of underlying OS differences
- Prerequisite installation order matters: Git → PowerShell 7 → .NET SDK → InvokeBuild module (same as Windows)
- Guard enforcement and exit codes provide cross-platform contract for automation and CI integration

