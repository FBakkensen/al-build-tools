# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AL Build Tools is a cross-platform PowerShell-based build toolkit for Microsoft AL (Business Central) projects. It provides a minimal, copy-only "overlay" that can be bootstrapped into any AL git repository and updated by running the same command again.

**Key Philosophy:**
- Copy-only overlay: no hidden state, just files under `overlay/`
- PowerShell 7.2+ first, cross-platform (Windows + Linux)
- Deterministic provisioning: compiler and symbols cached in user home directory
- Guarded entrypoints: scripts prevent accidental misuse outside supported invocation path
- Idempotent updates: rerun installer to pull new releases

## PowerShell Requirements

**CRITICAL:** Always run `pwsh` (PowerShell 7+) with the `-NoProfile` parameter as specified in the user's global CLAUDE.md instructions. This prevents user profile interference with build scripts.

Example: `pwsh -NoProfile -Command "& './scripts/make/build.ps1'"`

## Build System Architecture

### Two Build Orchestrators

The project uses **two separate build orchestrators** that coexist:

1. **Invoke-Build** (`overlay/al.build.ps1`) - Modern PowerShell task-based build system
   - Primary orchestrator for all build operations
   - Used by developers and CI/CD pipelines
   - Run with: `Invoke-Build <task>`
   - Default task is `test` (runs full test workflow)

2. **Makefile** (legacy, minimal) - Thin wrapper for backward compatibility
   - Provides familiar `make` commands
   - Delegates to PowerShell scripts via guard mechanism
   - Kept for projects that depend on Make-style interface

### Core Build Pipeline (Three Stages)

1. **download-compiler** - Provisions AL compiler as .NET tool
2. **download-symbols** - Downloads Business Central symbol packages
3. **build** - Compiles AL project with analyzers

### Common Build Commands

**Using Invoke-Build (recommended):**
```powershell
Invoke-Build                    # Default: run full test workflow
Invoke-Build build             # Compile main app only
Invoke-Build test              # Full test workflow (build → test → publish → run tests)
Invoke-Build publish           # Publish main app to BC server
Invoke-Build provision         # Set up environment (compiler + symbols)
Invoke-Build clean             # Remove build artifacts
Invoke-Build show-config       # Display configuration
Invoke-Build show-analyzers    # Show discovered analyzers
Invoke-Build ?                 # List all available tasks
```

**Using Make (if available):**
```bash
make build                     # Compile project
make clean                     # Remove artifacts
make show-config               # Display config
make show-analyzers            # Show analyzers
```

### Configuration Resolution (Three-Tier Priority)

Configuration is resolved in this order:
1. **Parameter** (highest priority) - passed to `Invoke-Build`
2. **Environment Variable** - set before invocation
3. **Default Value** - defined in `al.build.ps1`

Key configuration variables:
- `ALBT_APP_DIR` - App directory (default: `app`)
- `ALBT_TEST_DIR` - Test directory (default: `test`)
- `WARN_AS_ERROR` - Treat warnings as errors (default: `1`)
- `RULESET_PATH` - Analyzer ruleset file (default: `al.ruleset.json`)
- `ALBT_BC_SERVER_URL` - BC server URL (default: `http://bctest`)
- `ALBT_BC_SERVER_INSTANCE` - BC instance (default: `BC`)
- `ALBT_BC_CONTAINER_NAME` - Docker container name (default: `bctest`)

## Directory Structure

```
al-build-tools/
├── overlay/                    # Files copied to consuming projects
│   ├── al.build.ps1           # Invoke-Build orchestrator (NEW)
│   ├── scripts/
│   │   ├── common.psm1        # Shared utilities module
│   │   └── make/              # PowerShell entrypoints
│   │       ├── build.ps1      # Compilation script
│   │       ├── clean.ps1      # Cleanup script
│   │       ├── download-compiler.ps1
│   │       ├── download-symbols.ps1
│   │       ├── provision-local-symbols.ps1
│   │       ├── publish-app.ps1
│   │       ├── run-tests.ps1
│   │       ├── show-config.ps1
│   │       ├── show-analyzers.ps1
│   │       ├── new-bc-container.ps1
│   │       └── validate-breaking-changes.ps1
│   └── al.ruleset.json        # Analyzer ruleset
├── bootstrap/
│   └── install.ps1            # Bootstrap installer
├── scripts/
│   ├── ci/                    # CI-specific scripts
│   └── release/               # Release automation scripts
├── tests/                     # Pester test suites
│   ├── contract/              # Contract behavior tests
│   └── integration/           # Integration tests
└── specs/                     # Feature specifications
```

## Script Architecture

### Guard Policy

All entrypoint scripts under `overlay/scripts/make/*.ps1` use a **guard mechanism**:
- Scripts refuse to run unless `ALBT_VIA_MAKE=1` is set in the environment
- This prevents accidental misuse and ensures consistent behavior
- Exit code 2 if guard check fails

**Exception:** Helper scripts like `next-object-number.ps1` are not guarded.

### Shared Utilities Module (`common.psm1`)

The `overlay/scripts/common.psm1` module provides standardized functions:

**Exit Codes:**
- `Get-ExitCode` - Standard exit codes (Success=0, GeneralError=1, Guard=2, Analysis=3, Contract=4, Integration=5, MissingTool=6)

**Output Functions (ALWAYS USE THESE):**
- `Write-BuildMessage -Type <Info|Success|Warning|Error|Step|Detail> -Message "text"`
- `Write-BuildHeader "Section Title"`
- `Write-TaskHeader "TASK-NAME" "Description"`

**Path Utilities:**
- `Expand-FullPath` - Expand environment variables and resolve paths
- `ConvertTo-SafePathSegment` - Sanitize strings for filesystem use
- `Ensure-Directory` - Create directory if missing
- `New-TemporaryDirectory` - Create unique temp directory with GUID-based name

**Configuration:**
- `Get-AppJsonPath`, `Get-AppJsonObject` - Parse app.json
- `Get-SettingsJsonPath`, `Get-SettingsJsonObject` - Parse .vscode/settings.json
- `Get-OutputPath` - Compute expected .app file path
- `Read-JsonFile` - Read and parse JSON with error handling

**Cache Management:**
- `Get-ToolCacheRoot` - Get compiler cache directory (~/.bc-tool-cache)
- `Get-SymbolCacheRoot` - Get symbol cache directory (~/.bc-symbol-cache)
- `Get-LatestCompilerInfo` - Get latest compiler info from sentinel
- `Get-SymbolCacheInfo` - Get symbol cache manifest

**Analyzer Utilities:**
- `Get-EnabledAnalyzerPath` - Discover enabled analyzers from VS Code settings

**Business Central Integration:**
- `New-BCLaunchConfig` - Create minimal launch configuration
- `Get-BCCredential` - Create PSCredential for BC auth
- `Get-BCContainerName` - Resolve container name
- `Import-BCContainerHelper` - Import BC module with validation

### New Compiler Architecture (Latest-Only Principle)

**IMPORTANT:** The build system uses a "latest compiler only" approach:
- Single compiler version for all projects (no runtime-specific caching)
- Compiler stored at `~/.bc-tool-cache/al/`
- Sentinel file `sentinel.json` tracks the provisioned compiler
- No version selection logic - always uses the latest provisioned compiler

When working with compiler provisioning code:
- Do not introduce runtime-specific caching logic
- Do not create version-selection mechanisms
- Always reference the single sentinel at `~/.bc-tool-cache/al/sentinel.json`

## Development Guidelines

### PowerShell Scripting Standards

1. **Always use these headers:**
   ```powershell
   #requires -Version 7.2
   Set-StrictMode -Version Latest
   $ErrorActionPreference = 'Stop'
   ```

2. **Import common module:**
   ```powershell
   Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking
   ```

3. **Use standardized output:**
   ```powershell
   Write-BuildHeader "My Section"
   Write-BuildMessage -Type Step -Message "Doing something..."
   Write-BuildMessage -Type Success -Message "Operation completed"
   Write-BuildMessage -Type Detail -Message "Details here"
   Write-BuildMessage -Type Error -Message "Error occurred"
   ```

4. **Guard policy for entrypoints:**
   ```powershell
   if (-not $env:ALBT_VIA_MAKE) {
       Write-Output "Run via make (e.g., make build)"
       exit $Exit.Guard
   }
   ```

5. **Cross-platform compatibility:**
   - Use `$IsWindows`, `$IsLinux`, `$IsMacOS` for platform checks
   - Use forward slashes in paths where possible
   - Test on both Windows and Linux (WSL or CI)

6. **Line endings:**
   - PowerShell scripts use CRLF (enforced by `.gitattributes`)

### Static Analysis

The project uses PSScriptAnalyzer with strict rules:

**Run locally:**
```powershell
pwsh -NoProfile -Command @"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path overlay, bootstrap/install.ps1 -Recurse -Settings PSScriptAnalyzerSettings.psd1
"@
```

**Blocking rules (exit code 3 on violation):**
- PSAvoidUsingEmptyCatchBlock
- PSAvoidAssignmentToAutomaticVariable
- PSReviewUnusedParameter
- PSUseShouldProcessForStateChangingFunctions

**CI runs these checks automatically on PRs that touch `overlay/` or `bootstrap/`.**

### Testing

The repository uses Pester for testing:

**Run all tests:**
```powershell
pwsh -NoProfile -File scripts/run-tests.ps1 -CI
```

**Or invoke Pester directly:**
```powershell
Invoke-Pester -CI -Path tests/contract
Invoke-Pester -CI -Path tests/integration
```

**Test organization:**
- `tests/contract/` - Contract behavior tests (guards, diagnostics, FR-* requirements)
- `tests/integration/` - End-to-end integration tests

## Release Workflow

The project uses a **manual overlay-only release workflow**:

1. Maintainer triggers "Manual Overlay Release" GitHub Action
2. Workflow validates version, overlay cleanliness, tag uniqueness
3. Creates overlay ZIP with SHA-256 manifest
4. Publishes GitHub release with metadata block
5. Consumers can verify integrity using manifest

**Release artifacts:**
- `overlay.zip` (new format) or `al-build-tools-<version>.zip` (legacy)
- Embedded SHA-256 manifest (`manifest.sha256.txt`)
- Metadata JSON block in release notes (root_hash, commit, version)

See [specs/006-manual-release-workflow/quickstart.md](specs/006-manual-release-workflow/quickstart.md) for detailed workflow.

## Bootstrap Installation

Users install/update the overlay with this one-liner:

```powershell
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
```

**How it works:**
1. Downloads overlay ZIP from GitHub release
2. Extracts and copies `overlay/*` to destination
3. No state files, no backups - git tracks changes

**Version selection priority:**
1. `-Ref <tag>` parameter (e.g., `-Ref v1.2.3`)
2. `ALBT_RELEASE` environment variable
3. Latest published release (default)

## WSL Development Setup (Ubuntu 22.04/24.04)

For developing and testing in WSL:

```bash
# Install base packages
sudo apt-get update && sudo apt-get install -y curl gpg jq make

# Add Microsoft package repo and install PowerShell
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null
sudo apt-get update && sudo apt-get install -y powershell

# Install PowerShell modules
pwsh -NoLogo -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer,Pester -Scope CurrentUser -Force"

# Verify setup
pwsh --version
make --version
pwsh -NoLogo -NoProfile -Command "Get-Module PSScriptAnalyzer -ListAvailable | Select Name,Version"

# Run tests
pwsh -NoProfile -File scripts/run-tests.ps1 -CI
```

## Common Workflows

### Adding a New Build Script

1. Create script under `overlay/scripts/make/<script-name>.ps1`
2. Use standard headers and import common module
3. Add guard check for `ALBT_VIA_MAKE`
4. Use `Write-BuildMessage` for all output
5. Add task to `al.build.ps1` if needed
6. Update help documentation in `al.build.ps1`
7. Run PSScriptAnalyzer to validate
8. Add integration tests

### Modifying Existing Scripts

1. Read the script to understand current behavior
2. Import and use functions from `common.psm1`
3. Maintain cross-platform compatibility
4. Run PSScriptAnalyzer before committing
5. Test on both Windows and Linux if possible
6. Update relevant tests if behavior changes

### Working with Analyzers

Analyzers are discovered from `.vscode/settings.json`:
- Modern format: `al.codeAnalyzers` array
- Legacy format: `enableCodeCop`, `enableUICop`, etc.

Supported built-in analyzers:
- CodeCop
- UICop
- AppSourceCop
- PerTenantExtensionCop

Custom analyzers support path tokens:
- `${analyzerFolder}` - resolved from compiler's Analyzers directory
- `${alExtensionPath}` - resolved from compiler root
- `${compilerRoot}` - resolved from compiler root
- `${workspaceFolder}` - current workspace
- `${appDir}` - app directory

### Debugging Build Issues

1. Run with verbose output: `Invoke-Build build -Verbose`
2. Check configuration: `Invoke-Build show-config`
3. Verify analyzers: `Invoke-Build show-analyzers`
4. Inspect compiler sentinel: `~/.bc-tool-cache/al/sentinel.json`
5. Inspect symbol manifest: `~/.bc-symbol-cache/<publisher>/<app>/<id>/symbols.lock.json`
6. Enable verbose mode: `$VerbosePreference = 'Continue'`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Pull request workflow
- Commit message conventions
- Static analysis requirements
- Cross-platform testing expectations
- Line ending and encoding standards

**Key principles:**
- Keep entrypoints self-contained (no `lib/` folders)
- Maintain cross-OS support (Windows + Linux)
- Use standardized output functions from `common.psm1`
- Don't break existing entrypoints (stable API)
- Test on both platforms when possible
