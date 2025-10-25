# Research: Linux Installation Support

**Date**: 2025-10-25
**Status**: Phase 0 Complete
**Context**: Port Windows bootstrap installer to Ubuntu Linux with equivalent functionality

---

## Research Tasks Completed

### 1. Ubuntu Package Management for Prerequisites

**Decision**: Use apt package manager with Microsoft repositories for PowerShell 7 and .NET SDK

**Rationale**:
- Ubuntu's native apt package manager is standard across all Ubuntu LTS versions
- Microsoft provides official apt repositories for PowerShell 7 and .NET SDK on Ubuntu
- Git is available in default Ubuntu repositories
- Matches Windows pattern: use OS package manager (apt = apt, choco = chocolatey)

**Alternatives Considered**:
- Snap packages: Microsoft provides PowerShell via snap, but snap requires additional setup and has different path/permission model; less suitable for automated installs
- Manual binary downloads: Higher maintenance burden, no automatic updates, requires manual PATH management
- Build from source: Excessive complexity for prerequisites, slow installation time

**Implementation Notes**:
- Add Microsoft package repository: `wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb && dpkg -i packages-microsoft-prod.deb`
- Update apt cache: `apt-get update`
- Install PowerShell: `apt-get install -y powershell`
- Install .NET SDK: `apt-get install -y dotnet-sdk-8.0` (version from Windows installer)
- Install Git: `apt-get install -y git`

---

### 2. Sudo Privilege Escalation Pattern

**Decision**: Expect cached sudo session; users run `sudo -v` before installer

**Rationale**:
- Avoids embedding credential prompts in installer script
- Sudo sessions cache for 5-15 minutes by default (configurable in sudoers)
- Matches CI/container pattern: containers run with root or pre-cached sudo
- Clear error message when sudo unavailable allows user to fix and retry
- Aligns with spec requirement FR-014

**Alternatives Considered**:
- Interactive sudo prompts during install: Breaks auto-install mode for CI, creates inconsistent UX across Windows/Linux
- Require root user: Users prefer non-root installs; violates principle of least privilege
- Install to user space only: PowerShell 7 and .NET SDK system packages require root; user-space alternatives (snap, manual) less reliable

**Implementation Notes**:
- Check sudo availability: `sudo -n true 2>/dev/null` (non-interactive test)
- If fails, emit diagnostic: `[install] prerequisite tool="sudo" status="missing"` and exit with code 6 (MissingTool)
- Error message: "Sudo session required. Run 'sudo -v' to cache credentials, then retry installer."
- Document in quickstart: "Before running installer on Linux, run: sudo -v"

---

### 3. Apt Lock Conflict Handling

**Decision**: Retry with exponential backoff (5s, 10s, 20s), max 3 retries

**Rationale**:
- Ubuntu's unattended-upgrades can lock apt during background updates
- Lock files: `/var/lib/dpkg/lock-frontend`, `/var/lib/apt/lists/lock`
- Exponential backoff gives sufficient time for background processes to complete
- 3 retries = ~35 seconds total wait (5+10+20), balances patience vs timeout
- Matches industry pattern for resource contention (Docker pull, npm install)

**Alternatives Considered**:
- Immediate failure: Poor UX for temporary lock conditions; users encounter "apt locked" error frequently
- Longer retry cycles: >1 minute wait exceeds user patience threshold
- Kill locking processes: Dangerous; may corrupt package database; requires identifying process safely

**Implementation Notes**:
```powershell
$maxRetries = 3
$delays = @(5, 10, 20)
for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        & sudo apt-get update 2>&1 | Out-Null
        break
    } catch {
        if ($i -lt ($maxRetries - 1)) {
            $delay = $delays[$i]
            Write-Host "[install] prerequisite status=`"retry`" reason=`"apt-locked`" delay=`"${delay}s`""
            Start-Sleep -Seconds $delay
        } else {
            Write-Error "apt package manager locked after $maxRetries retries. Try: sudo fuser -vki /var/lib/dpkg/lock-frontend"
        }
    }
}
```

---

### 4. Docker Test Harness for Ubuntu

**Decision**: Adapt Windows test harness pattern using Ubuntu base image

**Rationale**:
- Windows test harness (`test-bootstrap-install.ps1`) provides proven pattern: provision container, run installer, capture output, generate JSON summary
- Ubuntu has official Docker images on Docker Hub: `ubuntu:22.04`, `ubuntu:20.04`
- Docker volume mounts allow capturing transcript and artifacts
- Same JSON summary schema enables unified CI reporting

**Alternatives Considered**:
- VM-based testing (Vagrant, multipass): Slower provisioning (minutes vs seconds), higher resource overhead
- Native Ubuntu CI runners (GitHub Actions ubuntu-latest): Cannot test clean install from scratch; pre-installed tools mask issues
- LXC/LXD containers: Less portable, Ubuntu-specific, requires host configuration

**Implementation Notes**:
- Base image: `ubuntu:22.04` (LTS, matches Windows ltsc2022 pattern)
- Environment variable: `ALBT_TEST_IMAGE` for version override
- Container lifecycle: `docker run --rm` (ephemeral) unless `ALBT_TEST_KEEP_CONTAINER=1`
- Volume mount: `-v ./out/test-install:/tmp/artifacts` for transcript/summary extraction
- Platform flag: Detect host OS and skip Linux tests on Windows (Windows containers cannot run Linux images)

---

### 5. Diagnostic Output Parity

**Decision**: Reuse Windows diagnostic marker format exactly

**Rationale**:
- Windows installer emits structured markers: `[install] prerequisite tool="git" status="check"`
- Cross-platform tooling (log parsers, CI dashboards) expects consistent format
- Same exit codes (0=Success, 2=Guard, 6=MissingTool) enable unified automation
- Spec requirement FR-005, FR-020

**Alternatives Considered**:
- Linux-specific format: Breaks cross-platform tooling; violates constitution principle of self-contained cross-platform scripts
- No structured markers: Difficult to parse for analytics; regression from Windows installer capabilities

**Implementation Notes**:
- Reuse `Write-BuildMessage` function pattern from Windows installer
- Step markers: `[install] step index=1 name=Check_Prerequisites`
- Guard markers: `[install] guard GitRepoRequired`
- Prerequisite markers: `[install] prerequisite tool="powershell" status="found" version="7.4.0"`
- Phase markers: `[install] phase name="prerequisite-installation" duration="42s"`

---

### 6. Interactive Prompt Validation

**Decision**: Display error with example, retry once after 2s, then fail

**Rationale**:
- Users make typos in interactive mode (Y/n prompts)
- Single retry handles accidental wrong key press without annoying users
- 2 second delay prevents rapid retry loop if input method broken
- Graceful failure with clear error message after retry maintains installer reliability
- Matches spec requirement FR-019

**Alternatives Considered**:
- Infinite retry loop: Can hang installer if input broken (e.g., piped non-interactive stdin)
- No retry: Harsh penalty for single typo
- Case-insensitive acceptance without validation: Silently accepts invalid input, may proceed unexpectedly

**Implementation Notes**:
```powershell
function Get-ValidatedInput {
    param([string]$Prompt, [string[]]$ValidInputs, [string]$Example)

    for ($retry = 0; $retry -lt 2; $retry++) {
        $response = Read-Host $Prompt
        if ($response -in $ValidInputs) {
            return $response
        }
        if ($retry -eq 0) {
            Write-Host "[install] input status=`"invalid`" example=`"$Example`""
            Start-Sleep -Seconds 2
        } else {
            Write-Error "Invalid input '$response'. Expected: $Example"
        }
    }
}
```

---

### 7. Bootstrap Installer Language (Bash vs PowerShell)

**Decision**: Linux bootstrap installer must be bash script; delegate to PowerShell after installation

**Rationale**:
- **Critical**: PowerShell is a prerequisite to be installed, creating circular dependency if installer written in PowerShell
- Bash is pre-installed on all Ubuntu systems
- Matches Windows pattern: Windows installer can start with PowerShell 5.1 (pre-installed), then upgrade to PS 7
- Linux has no PowerShell pre-installed, so bash must bootstrap the installation
- After PowerShell installed, bash can invoke PowerShell for complex operations or delegate to overlay scripts

**Alternatives Considered**:
- PowerShell installer: REJECTED - Cannot run PowerShell installer if PowerShell not yet installed (circular dependency)
- Python installer: Not as universally available as bash; adds unnecessary dependency
- C/compiled binary: Excessive complexity for installer script; hard to maintain

**Implementation Notes**:
```bash
#!/bin/bash
# bootstrap/install-linux.sh
set -euo pipefail

# Phase 1: Detect and install prerequisites using bash + apt
# - Check for sudo session
# - Install PowerShell 7 via apt
# - Install .NET SDK via apt
# - Install Git if missing

# Phase 2: After PowerShell installed, delegate to PowerShell for:
# - Installing InvokeBuild module (requires PowerShell)
# - Downloading overlay (can use curl in bash OR pwsh Invoke-WebRequest)
# - Git operations (can use git CLI in bash)

# Example delegation after PS7 installed:
if command -v pwsh &> /dev/null; then
    pwsh -Command "Install-Module InvokeBuild -Scope CurrentUser -Force"
fi
```

**File Structure**:
- `bootstrap/install-linux.sh` - Bash script (main entry point)
- `bootstrap/install-prerequisites-linux.sh` - Bash script (apt operations)
- Overlay scripts remain PowerShell (executed after prerequisites installed)

---

### 8. Overlay Download Integrity Validation

**Decision**: Test archive extraction after download (no SHA256 validation)

**Rationale**:
- Matches Windows installer behavior (spec requirement FR-008)
- Extraction test (`Expand-Archive`) detects corrupt zip files
- SHA256 validation optional (can be added later without breaking contract)
- GitHub releases use TLS; transport-level integrity sufficient for v1

**Alternatives Considered**:
- SHA256 manifest validation: Requires publishing SHA256 alongside overlay.zip; adds release workflow complexity
- No validation: Corrupt downloads cause cryptic errors during file copy

**Implementation Notes**:
```powershell
try {
    Expand-Archive -Path $overlayZip -DestinationPath $tempExtract -Force
} catch {
    Write-Host "[install] diagnostic category=`"CorruptArchive`" hint=`"Re-download overlay.zip`""
    Write-Error "Overlay archive corrupted. Try again or download manually."
}
```

---

## Summary of Technical Decisions

| Area | Decision | Key Benefits |
|------|----------|--------------|
| Package Management | apt + Microsoft repos | Standard Ubuntu pattern, official packages |
| Sudo Handling | Cached session (user runs `sudo -v`) | Clean separation, CI-friendly |
| Apt Lock Conflicts | Exponential backoff (5s, 10s, 20s) | Handles transient locks gracefully |
| Test Infrastructure | Docker Ubuntu containers | Fast, ephemeral, mirrors Windows pattern |
| Diagnostic Output | Exact Windows marker format | Cross-platform tooling compatibility |
| Input Validation | Error + retry once + fail | Balance usability and reliability |
| Installer Language | Bash for bootstrap, PowerShell after install | Breaks circular dependency, bash universally available |
| Archive Integrity | Extraction test only | Matches Windows, simple implementation |

---

## Open Questions (Resolved)

1. ~~How to handle sudo password prompts in auto-install mode?~~
   **Resolved**: Expect cached sudo session; fail with MissingTool if unavailable

2. ~~Should installer mask credentials in logs?~~
   **Resolved**: No masking; maximum transparency for debugging (spec clarification)

3. ~~How to handle apt lock conflicts?~~
   **Resolved**: Retry with exponential backoff, fail after 3 attempts

4. ~~What input validation for interactive prompts?~~
   **Resolved**: Show error with example, retry once, then fail

5. ~~How to validate overlay integrity?~~
   **Resolved**: Test extraction only, matching Windows installer

---

## References

- Windows installer implementation: `bootstrap/install.ps1`, `bootstrap/install-prerequisites.ps1`
- Windows test harness: `scripts/ci/test-bootstrap-install.ps1`
- Microsoft PowerShell on Ubuntu: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu
- Microsoft .NET on Ubuntu: https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu
- Docker Ubuntu images: https://hub.docker.com/_/ubuntu
- Ubuntu apt lock handling: https://askubuntu.com/questions/15433/unable-to-lock-the-administration-directory-var-lib-dpkg-is-another-process

---

**Phase 0 Status**: ✅ COMPLETE - All NEEDS CLARIFICATION items resolved, ready for Phase 1 design
