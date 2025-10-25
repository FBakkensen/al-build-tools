# Data Model: Linux Installation Support

**Date**: 2025-10-25
**Status**: Phase 1 Complete (Updated for Bash installer)
**Context**: Define entities and their relationships for Linux installer and test harness

**Note**: Linux bootstrap installer implemented in bash (not PowerShell) since PowerShell is a prerequisite to install. After PowerShell installed, bash may delegate to PowerShell for module installation (InvokeBuild).

---## Core Entities

### 1. InstallerConfiguration

Configuration state for Linux bootstrap installer execution.

**Fields**:
- `Url`: string - GitHub API base URL (default: https://api.github.com/repos/FBakkensen/al-build-tools)
- `Ref`: string - Release tag to install (e.g., "v1.0.0", "latest")
- `DestinationPath`: string - Target directory for overlay installation (default: ".")
- `Source`: string - Source folder within overlay archive (default: "overlay")
- `HttpTimeoutSec`: int - Network timeout for downloads (default: 30)
- `AutoInstall`: bool - Enable non-interactive mode (from ALBT_AUTO_INSTALL env var)

**Validation Rules**:
- `Url` must be valid GitHub API URL
- `DestinationPath` must be writable directory
- `Ref` must be valid git tag or "latest"
- `HttpTimeoutSec` must be positive integer or 0 (no timeout)

**Relationships**:
- Used by → `InstallerExecutionContext`
- Produces → `ReleaseMetadata`

---

### 2. PrerequisiteTool

Individual prerequisite tool required for AL Build Tools.

**Fields**:
- `Name`: string - Tool identifier ("git", "powershell", "dotnet", "InvokeBuild")
- `DetectionCommand`: string - Bash/shell command to test presence (e.g., "command -v git", "pwsh --version")
- `ExpectedVersion`: string (optional) - Minimum version required
- `InstallCommand`: string - apt command (git, powershell, dotnet) or pwsh command (InvokeBuild module)
- `PackageName`: string - apt package name ("git", "powershell", "dotnet-sdk-8.0") or PowerShell module ("InvokeBuild")
- `Status`: enum - "missing", "found", "installed", "failed"
- `InstalledVersion`: string (optional) - Detected version after installation

**Validation Rules**:
- `Name` must be one of: git, powershell, dotnet, InvokeBuild
- `Status` transitions: missing → found (detected) OR missing → installed (installed successfully)
- `DetectionCommand` must exit 0 when tool present

**State Transitions**:
```
missing → found          (tool already installed on system)
missing → installed      (installer successfully installed tool)
missing → failed         (installation failed)
found → found            (no action needed)
```

**Relationships**:
- Aggregated by → `PrerequisiteSummary`
- Referenced in → `InstallationPhase` (prerequisite-installation)

---

### 3. PrerequisiteSummary

Aggregate status of all prerequisite checks and installations.

**Fields**:
- `Tools`: array of `PrerequisiteTool` - All required prerequisites
- `AllPresent`: bool - True if all tools detected (no installation needed)
- `AnyFailed`: bool - True if any installation failed
- `InstallationRequired`: bool - True if any tools missing before installation
- `SudoCached`: bool - True if sudo session available (Linux-specific)

**Validation Rules**:
- Must contain exactly 4 tools: git, powershell, dotnet, InvokeBuild
- `AllPresent` = true only if all tools have status "found" or "installed"
- `AnyFailed` = true if any tool has status "failed"

**Relationships**:
- Contains → `PrerequisiteTool` (4 instances)
- Referenced by → `InstallationSummary`

---

### 4. InstallationPhase

Timed execution phase during installation.

**Fields**:
- `Name`: string - Phase identifier ("release-resolution", "prerequisite-installation", "overlay-download", "file-copy", "git-commit")
- `StartTime`: datetime - Phase start timestamp
- `EndTime`: datetime (optional) - Phase end timestamp (null if in progress)
- `Duration`: string - Human-readable duration (e.g., "42s", "1m 23s")
- `Status`: enum - "in-progress", "completed", "failed", "skipped"
- `ErrorMessage`: string (optional) - Error details if failed

**Validation Rules**:
- `Name` must be one of predefined phase names
- `EndTime` must be after `StartTime` when present
- `Duration` calculated as `EndTime - StartTime`
- `Status` = "completed" requires `EndTime` present

**State Transitions**:
```
in-progress → completed      (phase succeeded)
in-progress → failed         (phase encountered error)
in-progress → skipped        (phase skipped due to earlier failure)
```

**Relationships**:
- Aggregated by → `InstallationSummary`

---

### 5. DiagnosticMarker

Structured diagnostic output emitted during installation.

**Fields**:
- `Type`: enum - "prerequisite", "step", "guard", "phase", "diagnostic"
- `Category`: string (optional) - Error category (e.g., "GitRepoRequired", "CorruptArchive")
- `Tool`: string (optional) - Tool name for prerequisite markers
- `Status`: string (optional) - Status for prerequisite/step markers
- `Index`: int (optional) - Step index for step markers
- `Name`: string (optional) - Step name for step markers
- `Hint`: string (optional) - User-facing hint for diagnostic markers
- `RawOutput`: string - Original marker line from output

**Validation Rules**:
- Must match pattern: `[install] <type> key1="value1" key2="value2"`
- Prerequisite markers must include `tool` and `status`
- Guard markers must include `category`
- Step markers must include `index` and `name`

**Format Examples**:
```
[install] prerequisite tool="git" status="check"
[install] prerequisite tool="powershell" status="found" version="7.4.0"
[install] step index=1 name=Check_Prerequisites
[install] guard GitRepoRequired
[install] diagnostic category="CorruptArchive" hint="Re-download overlay.zip"
[install] phase name="prerequisite-installation" duration="42s"
```

**Relationships**:
- Aggregated by → `InstallationSummary` (diagnostics array)

---

### 6. ReleaseMetadata

GitHub release information resolved during installation.

**Fields**:
- `TagName`: string - Release tag (e.g., "v1.0.0")
- `AssetUrl`: string - Direct URL to overlay.zip asset
- `AssetSize`: int - Size of overlay.zip in bytes
- `PublishedAt`: datetime - Release publication timestamp
- `IsDraft`: bool - True if release is draft (should be skipped)
- `IsPrerelease`: bool - True if release is pre-release

**Validation Rules**:
- `TagName` must match semantic version pattern or "latest"
- `AssetUrl` must be valid HTTPS URL
- `AssetSize` must be positive integer
- Draft releases (IsDraft=true) excluded from "latest" resolution

**Relationships**:
- Resolved from → `InstallerConfiguration.Ref`
- Referenced by → `InstallationSummary`

---

### 7. GitRepositoryState

Git repository status before and after installation.

**Fields**:
- `IsRepository`: bool - True if destination is git repository
- `IsClean`: bool - True if working tree clean (no uncommitted changes)
- `CurrentBranch`: string (optional) - Active branch name
- `HasInitialCommit`: bool - True if repository has at least one commit
- `CommitCreated`: bool - True if installer created commit
- `CommitHash`: string (optional) - SHA of created commit

**Validation Rules**:
- If `IsRepository` = false, installer must fail with guard violation
- If `IsClean` = false, installer must fail with guard violation
- If `HasInitialCommit` = false, installer creates initial commit with overlay

**Relationships**:
- Referenced by → `InstallationSummary`

---

### 8. InstallationSummary

Complete execution summary for test harness and diagnostics.

**Fields**:
- `Metadata`: object
  - `TestHarness`: string - Test script name
  - `ExecutionTime`: datetime - Test start timestamp
  - `ContainerImage`: string - Docker image used
  - `ReleaseTag`: string - Tested release tag
- `Prerequisites`: `PrerequisiteSummary` - Prerequisite status
- `Phases`: array of `InstallationPhase` - Timed execution phases
- `GitState`: `GitRepositoryState` - Repository status
- `Release`: `ReleaseMetadata` - Resolved release information
- `ExitCode`: int - Installer exit code
- `ExitCategory`: string - Exit code category ("success", "guard", "missing-tool")
- `Diagnostics`: array of `DiagnosticMarker` - Parsed diagnostic markers
- `Success`: bool - True if installation succeeded (exit code 0)

**Validation Rules**:
- Must conform to `test-summary-schema.json`
- `ExitCode` must be valid (0, 1, 2, 6)
- `Success` = true only if `ExitCode` = 0
- `Phases` must include at least: release-resolution, prerequisite-installation

**Relationships**:
- Top-level aggregate containing all other entities
- Persisted as → `summary.json` artifact

---

### 9. TestScenario

Docker-based test scenario configuration.

**Fields**:
- `Name`: string - Scenario identifier (e.g., "fresh-ubuntu-22.04")
- `BaseImage`: string - Docker image (e.g., "ubuntu:22.04")
- `PrerequisiteOverride`: string (optional) - Pre-install specific tools
- `ExpectedExitCode`: int - Expected installer exit code
- `ExpectedCategory`: string - Expected exit category
- `ValidationRules`: array of string - Post-install assertions

**Validation Rules**:
- `BaseImage` must be valid Docker image reference
- `ExpectedExitCode` must match installer exit code semantics
- `ValidationRules` executed after container provisioning

**Example Scenarios**:
1. Fresh Ubuntu 22.04 (nothing pre-installed)
2. Partial prerequisites (git pre-installed, PS7 missing)
3. Network failure simulation
4. Git guard violations (no repo, dirty working tree)

**Relationships**:
- Executed by → Test Harness
- Produces → `InstallationSummary`

---

## Entity Relationships Diagram

```
InstallerConfiguration
    ↓ configures
InstallerExecutionContext
    ↓ resolves
ReleaseMetadata
    ↓ downloads
OverlayArchive
    ↓ extracts to
GitRepositoryState
    ↓ verifies
GuardValidation
    ↓ proceeds with
PrerequisiteDetection
    ↓ produces
PrerequisiteSummary
    ↓ contains 4×
PrerequisiteTool
    ↓ installs missing
PrerequisiteInstallation
    ↓ creates
InstallationPhase (multiple)
    ↓ emits
DiagnosticMarker (multiple)
    ↓ aggregated into
InstallationSummary
    ↓ persisted as
summary.json artifact
```

---

## Data Flow

### 1. Installer Execution Flow

```
[Start] → Parse Parameters → Validate Git Repo → Check Prerequisites
    ↓                              ↓                       ↓
LoadConfig                   Guard Checks          Detect Tools
    ↓                              ↓                       ↓
Resolve Release              Exit if Failed        Install Missing
    ↓                                                      ↓
Download Overlay                                     Create Summary
    ↓
Extract Archive
    ↓
Copy Files
    ↓
Git Commit
    ↓
[Success]
```

### 2. Test Harness Flow

```
[Start] → Provision Container → Run Installer → Capture Output
    ↓                                  ↓                 ↓
Load Config                      Volume Mount      Parse Diagnostics
    ↓                                  ↓                 ↓
Pull Image                       Execute Script    Extract Phases
    ↓                                  ↓                 ↓
Start Container                  Wait for Exit     Build Summary
    ↓                                  ↓                 ↓
[Container Ready]           [Exit Code]        [Generate JSON]
                                                        ↓
                                                 [Validate Schema]
```

---

## Persistence

### File Artifacts

1. **install.transcript.txt**
   - Raw PowerShell transcript
   - Includes all Write-Host, Write-Verbose, error messages
   - Used for diagnostic marker extraction

2. **summary.json**
   - Structured `InstallationSummary` object
   - Conforms to `test-summary-schema.json`
   - Used for CI reporting and analytics

3. **provision.log**
   - Container setup details
   - Docker commands and output
   - Generated on failure for debugging

---

## Cross-Platform Compatibility

### Windows vs Linux Entities

| Entity | Windows | Linux | Notes |
|--------|---------|-------|-------|
| PrerequisiteTool | Chocolatey | apt | Different package managers |
| PrerequisiteTool.PackageName | "git.install" | "git" | Different package naming |
| PrerequisiteSummary.SudoCached | N/A | Required | Linux-specific field |
| InstallationPhase | Same | Same | Identical phase names |
| DiagnosticMarker | Same | Same | Exact format match required |
| ExitCode | Same | Same | Cross-platform contract |

---

**Phase 1 Status**: ✅ Data model complete, ready for contract generation
