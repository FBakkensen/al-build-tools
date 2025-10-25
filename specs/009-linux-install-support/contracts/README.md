# Contracts: Linux Installation Support

**Purpose**: Define API contracts, schemas, and interfaces for Linux installer and test harness

---

## Contents

### 1. exit-codes.md

Exit code reference for Linux installer matching Windows installer semantics.

**Key Contracts**:
- Exit code 0: Installation success
- Exit code 2: Guard violation (unknown parameter, missing git repo, dirty working tree)
- Exit code 6: Missing tool (sudo unavailable, apt locked, prerequisite installation failed)
- Exit code 1: General error (network timeout, corrupt archive, disk full)

**Usage**: CI scripts, automation tools, diagnostic analysis

---

### 2. test-summary-schema.json

JSON schema for installer test harness summary artifacts (Windows and Linux).

**Structure**:
- `metadata`: Test execution context (harness name, timestamp, container image, release tag)
- `prerequisites`: Prerequisite tool status (4 tools: git, powershell, dotnet, InvokeBuild)
- `phases`: Timed execution phases (release-resolution, prerequisite-installation, overlay-download, file-copy, git-commit)
- `gitState`: Repository status (isRepository, isClean, commitCreated, commitHash)
- `release`: Resolved release metadata (tagName, assetUrl, assetSize)
- `exitCode`: Installer exit code (0, 1, 2, 6)
- `exitCategory`: Exit code category name (success, guard, missing-tool, general-error)
- `diagnostics`: Parsed diagnostic markers from installer output
- `success`: Boolean flag (true if exit code 0)

**Usage**: Test harness output validation, CI reporting, analytics

**Example**:
```json
{
  "metadata": {
    "testHarness": "test-bootstrap-install-linux.ps1",
    "executionTime": "2025-10-25T10:30:00Z",
    "containerImage": "ubuntu:22.04",
    "releaseTag": "v1.0.0",
    "platform": "Linux"
  },
  "prerequisites": {
    "tools": [
      {"name": "git", "status": "installed", "version": "2.34.1"},
      {"name": "powershell", "status": "installed", "version": "7.4.0"},
      {"name": "dotnet", "status": "installed", "version": "8.0.100"},
      {"name": "InvokeBuild", "status": "installed"}
    ],
    "allPresent": false,
    "anyFailed": false,
    "installationRequired": true,
    "sudoCached": true
  },
  "phases": [
    {
      "name": "release-resolution",
      "startTime": "2025-10-25T10:30:05Z",
      "endTime": "2025-10-25T10:30:08Z",
      "duration": "3s",
      "status": "completed"
    },
    {
      "name": "prerequisite-installation",
      "startTime": "2025-10-25T10:30:08Z",
      "endTime": "2025-10-25T10:30:50Z",
      "duration": "42s",
      "status": "completed"
    }
  ],
  "gitState": {
    "isRepository": true,
    "isClean": true,
    "currentBranch": "main",
    "hasInitialCommit": false,
    "commitCreated": true,
    "commitHash": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"
  },
  "exitCode": 0,
  "exitCategory": "success",
  "success": true
}
```

---

### 3. installer-diagnostic-schema.json

JSON schema for individual diagnostic markers emitted during installation.

**Marker Types**:
- `prerequisite`: Tool detection and installation status
- `step`: Installation step progression
- `guard`: Guard condition violations
- `phase`: Timed execution phase completion
- `diagnostic`: Error diagnostics with hints
- `input`: Interactive input validation

**Format**: `[install] <type> key1="value1" key2="value2"`

**Examples**:
```
[install] prerequisite tool="git" status="check"
[install] prerequisite tool="powershell" status="found" version="7.4.0"
[install] prerequisite status="retry" reason="apt-locked" delay="5s"
[install] step index=1 name=Check_Prerequisites
[install] guard GitRepoRequired
[install] phase name="prerequisite-installation" duration="42s"
[install] diagnostic category="CorruptArchive" hint="Re-download overlay.zip"
[install] input status="invalid" example="Y/n"
```

**Usage**: Real-time log parsing, diagnostic extraction, cross-platform parity validation

---

## Cross-Platform Parity

All contracts designed for Windows/Linux compatibility:

| Contract Element | Windows | Linux | Notes |
|------------------|---------|-------|-------|
| Exit codes | Same | Same | Identical semantics |
| Diagnostic markers | Same | Same | Exact format match |
| JSON schema | Same | Same | Platform field differentiates |
| Test summary structure | Same | Same | Prerequisites differ (choco vs apt) |
| Phase names | Same | Same | Identical progression |

---

## Validation

### Schema Validation

```powershell
# Validate summary.json against schema
$schema = Get-Content contracts/test-summary-schema.json | ConvertFrom-Json
$summary = Get-Content out/test-install/summary.json | ConvertFrom-Json

# Use JSON schema validator (e.g., ajv-cli)
ajv validate -s contracts/test-summary-schema.json -d out/test-install/summary.json
```

### Exit Code Testing

```powershell
# Test exit code contract
$exitCode = $LASTEXITCODE
$expectedCategory = 'success'

$categoryMap = @{
    0 = 'success'
    1 = 'general-error'
    2 = 'guard'
    6 = 'missing-tool'
}

if ($categoryMap[$exitCode] -ne $expectedCategory) {
    Write-Error "Exit code mismatch: expected $expectedCategory, got $($categoryMap[$exitCode])"
}
```

---

## Contract Evolution

### Versioning

Contracts follow semantic versioning:
- **Major**: Breaking changes (incompatible schema, removed fields)
- **Minor**: Backward-compatible additions (new diagnostic types, new phases)
- **Patch**: Clarifications, documentation updates

### Backward Compatibility

- Test harness must accept older summary formats (forward compatibility)
- New diagnostic marker types are additive (existing parsers ignore unknown types)
- Exit codes are stable (no reassignment without major version bump)

---

## References

- Feature specification: `../spec.md`
- Data model: `../data-model.md`
- Windows installer contracts: Implied by `bootstrap/install.ps1` behavior
- Constitution: `.github/copilot-instructions.md` (exit code policy, cross-platform parity)

---

**Status**: ✅ Contracts complete, ready for implementation
