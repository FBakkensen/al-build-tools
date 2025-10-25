# Exit Codes Reference

**Context**: Linux installer exit code contract matching Windows installer

**Version**: 1.0.0
**Date**: 2025-10-25

---

## Standard Exit Codes

All AL Build Tools installer scripts (Windows and Linux) use standardized exit codes for automation and CI integration.

| Code | Category | Description | When Used |
|------|----------|-------------|-----------|
| 0 | Success | Installation completed successfully | All prerequisites installed, overlay copied, git commit created |
| 1 | GeneralError | Non-specific failure | Network errors, file I/O errors, unexpected exceptions |
| 2 | Guard | Guard condition violated | Unknown parameters, missing git repo, dirty working tree |
| 3 | Analysis | Static analysis failure | (Not used by installer; reserved for build scripts) |
| 4 | Contract | Contract violation | (Not used by installer; reserved for build scripts) |
| 5 | Integration | Integration failure | (Not used by installer; reserved for build scripts) |
| 6 | MissingTool | Required tool unavailable | Sudo session expired, apt unavailable, PowerShell 7 installation failed |

---

## Linux Installer Specific Exit Scenarios

### Exit Code 0 (Success)

**Conditions**:
- All prerequisites detected or installed successfully
- Overlay archive downloaded and extracted
- Files copied to destination directory
- Git commit created (or skipped if already committed)
- No errors during any phase

**Example Output**:
```
[install] phase name="git-commit" duration="1s"
[+] Installation completed successfully
```

---

### Exit Code 1 (GeneralError)

**Conditions**:
- Network timeout during release resolution or overlay download
- Disk full during extraction or file copy
- Invalid input in interactive prompt (after retry)
- Corrupt overlay archive (extraction failed)
- Unexpected exception during execution

**Example Output**:
```
[install] diagnostic category="NetworkTimeout" hint="Check internet connection and retry"
[X] Installation failed: Network timeout during overlay download
```

**Common Causes**:
- No internet connectivity
- GitHub API rate limit exceeded
- Insufficient disk space
- Corrupt download

---

### Exit Code 2 (Guard)

**Conditions**:
- Unknown parameter provided
- Destination is not a git repository
- Git working tree has uncommitted changes
- Invalid parameter values

**Example Output (Unknown Parameter)**:
```
[install] guard UnknownParameter argument="BadParam"
Usage: install-linux.ps1 [-Url <url>] [-Ref <ref>] [-DestinationPath <path>] [-Source <folder>]
Installation failed: Unknown parameter 'BadParam'. Use: install-linux.ps1 [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]
```

**Example Output (Git Repository Required)**:
```
[install] guard GitRepoRequired
Installation failed: Destination must be a git repository. Run 'git init' first.
```

**Example Output (Clean Working Tree Required)**:
```
[install] guard CleanWorkingTreeRequired
Installation failed: Git working tree has uncommitted changes. Commit or stash changes before installing.
```

**Common Causes**:
- Typo in parameter name
- Running outside git repository
- Forgetting to commit local changes

---

### Exit Code 6 (MissingTool)

**Conditions**:
- Sudo session not cached (user needs to run `sudo -v`)
- apt package manager unavailable
- PowerShell 7 installation failed
- .NET SDK installation failed
- InvokeBuild module installation failed

**Example Output (Sudo Required)**:
```
[install] prerequisite tool="sudo" status="missing"
Installation failed: Sudo session required. Run 'sudo -v' to cache credentials, then retry installer.
```

**Example Output (apt Locked After Retries)**:
```
[install] prerequisite status="retry" reason="apt-locked" delay="5s"
[install] prerequisite status="retry" reason="apt-locked" delay="10s"
[install] prerequisite status="retry" reason="apt-locked" delay="20s"
Installation failed: apt package manager locked after 3 retries. Try: sudo fuser -vki /var/lib/dpkg/lock-frontend
```

**Example Output (PowerShell Installation Failed)**:
```
[install] prerequisite tool="powershell" status="failed"
Installation failed: PowerShell 7 installation failed. Check network connectivity and Microsoft package repository availability.
```

**Common Causes**:
- Sudo session expired
- Another process holding apt lock (unattended-upgrades)
- Microsoft package repository unreachable
- Disk full during package installation

---

## CI Integration Examples

### Bash Script Example

```bash
#!/bin/bash
pwsh -File bootstrap/install-linux.ps1
exitCode=$?

case $exitCode in
    0)
        echo "✅ Installation succeeded"
        ;;
    1)
        echo "❌ General error - check logs"
        exit 1
        ;;
    2)
        echo "⛔ Guard violation - fix parameters or git state"
        exit 1
        ;;
    6)
        echo "🔧 Missing tool - install prerequisites"
        exit 1
        ;;
    *)
        echo "❓ Unknown exit code: $exitCode"
        exit 1
        ;;
esac
```

### GitHub Actions Example

```yaml
- name: Install AL Build Tools
  run: |
    sudo -v  # Cache sudo session
    pwsh -File bootstrap/install-linux.ps1

- name: Check Exit Code
  if: failure()
  run: |
    echo "Exit code: $?"
    if [ $? -eq 2 ]; then
      echo "::error::Guard violation - check parameters and git state"
    elif [ $? -eq 6 ]; then
      echo "::error::Missing prerequisite tool"
    fi
```

---

## Comparison with Windows Installer

| Scenario | Windows Exit Code | Linux Exit Code | Notes |
|----------|-------------------|-----------------|-------|
| Success | 0 | 0 | Identical |
| Unknown parameter | 2 | 2 | Identical |
| Not a git repo | 2 | 2 | Identical |
| Dirty working tree | 2 | 2 | Identical |
| Chocolatey unavailable | 6 | N/A | Windows-specific |
| Sudo unavailable | N/A | 6 | Linux-specific |
| apt locked | N/A | 6 | Linux-specific |
| Network timeout | 1 | 1 | Identical |
| Corrupt archive | 1 | 1 | Identical |

---

## Testing Exit Codes

Test harness validates exit codes across scenarios:

```powershell
# Test scenario: Fresh install (expect success)
$result = & docker run ubuntu:22.04 pwsh -File /tmp/install-linux.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Expected exit code 0, got $LASTEXITCODE"
}

# Test scenario: Missing git repo (expect guard)
$result = & docker run ubuntu:22.04 pwsh -File /tmp/install-linux.ps1 -Dest /tmp/not-a-repo
if ($LASTEXITCODE -ne 2) {
    Write-Error "Expected exit code 2 (Guard), got $LASTEXITCODE"
}

# Test scenario: Expired sudo (expect missing tool)
$result = & docker run --user nonroot ubuntu:22.04 pwsh -File /tmp/install-linux.ps1
if ($LASTEXITCODE -ne 6) {
    Write-Error "Expected exit code 6 (MissingTool), got $LASTEXITCODE"
}
```

---

## Exit Code Enforcement

**Constitution Requirement**: "Scripts MUST return standardized exit codes (0 success, 1 general error, 2 guard, 3 analysis, 4 contract, 5 integration, 6 missing tool) and avoid silent failure paths."

**Implementation**:
- Explicit `exit <code>` statements at failure points
- `$ErrorActionPreference = 'Stop'` prevents silent failures
- Guard checks emit diagnostic and exit 2
- Tool installation failures exit 6
- All other errors exit 1

**Testing**:
- Pester tests validate exit codes per scenario
- Test harness captures and reports exit code in summary.json
- CI fails if exit code doesn't match expected value

---

**Version History**:
- 1.0.0 (2025-10-25): Initial version for Linux installer
