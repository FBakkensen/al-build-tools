#requires -Version 7.2

<#
.SYNOPSIS
    AL Project Build System using Invoke-Build

.DESCRIPTION
    PowerShell-based build automation for AL (Business Central) projects.
    Migrated from Make to Invoke-Build for better PowerShell integration.

    Maintains the existing three-stage pipeline:
    - download-compiler: Install/update AL compiler dotnet tool
    - download-symbols: Download required Business Central symbol packages
    - build: Compile the AL project with analysis

.PARAMETER AppDir
    Directory containing the AL project files and app.json (defaults to current directory)

.PARAMETER WarnAsError
    Treat AL compiler warnings as errors (1 to enable, 0 to disable, default: 1)

.PARAMETER RulesetPath
    Optional ruleset file for analyzers (default: al.ruleset.json)

.EXAMPLE
    Invoke-Build
    Runs the default 'build' task with all dependencies

.EXAMPLE
    Invoke-Build build -WarnAsError "0" -Verbose
    Build without treating warnings as errors, with verbose output

.EXAMPLE
    Invoke-Build ?
    Show all available tasks

.NOTES
    Preserves the existing PowerShell script architecture under scripts/make/
    All scripts remain self-contained and use the ALBT_VIA_MAKE guard mechanism.
#>

[CmdletBinding()]
param(
    [string]$AppDir,
    [string]$TestDir,
    [ValidateSet("0", "1")]
    [string]$WarnAsError,
    [string]$RulesetPath,
    [string]$ServerUrl,
    [string]$ServerInstance,
    [string]$ContainerName,
    [string]$ContainerUsername,
    [string]$ContainerPassword,
    [string]$ContainerAuth,
    [string]$ArtifactCountry,
    [string]$ArtifactSelect,
    [string]$Tenant,
    [ValidateSet("0", "1")]
    [string]$ValidateCurrent
)

# =============================================================================
# Project Configuration (tweak as needed when bootstrapping)
# =============================================================================
# Directory containing the AL project files and app.json
$DefaultAppDir = "app"
$DefaultTestDir = "test"

# Build Options
$DefaultWarnAsError = "1"                    # Treat AL compiler warnings as errors (1 to enable, 0 to disable)
$DefaultRulesetPath = "al.ruleset.json"      # Optional ruleset file for analyzers (leave empty to disable)

# Business Central Server Configuration
$DefaultServerUrl = "http://bctest"          # Business Central server URL
$DefaultServerInstance = "BC"                # Business Central server instance name

# Business Central Container Configuration
$DefaultContainerName = "bctest"             # BC Docker container name
$DefaultContainerUsername = "admin"          # BC container admin username
$DefaultContainerPassword = "P@ssw0rd"       # BC container admin password (non-secret, local dev)
$DefaultContainerAuth = "UserPassword"       # BC container authentication type
$DefaultArtifactCountry = "w1"               # BC artifact country code
$DefaultArtifactSelect = "Latest"            # BC artifact version selection
$DefaultTenant = "default"                   # BC tenant name

# AL Validation Configuration
$DefaultValidateCurrent = "1"                # Validate against current BC version (1 to enable, 0 to disable)

# =============================================================================
# Three-Tier Configuration Resolution using PowerShell 7+ coalescing operators
# Priority: 1. Parameter → 2. Environment Variable → 3. File Setting
# =============================================================================

# Elegant configuration resolution using null coalescing operator (??)
# Each ?? moves to the next value if the previous is null or empty
$AppDir = ($AppDir | Where-Object { $_ }) ?? ($env:ALBT_APP_DIR | Where-Object { $_ }) ?? $DefaultAppDir
$TestDir = ($TestDir | Where-Object { $_ }) ?? ($env:ALBT_TEST_DIR | Where-Object { $_ }) ?? $DefaultTestDir
$WarnAsError = ($WarnAsError | Where-Object { $_ }) ?? ($env:WARN_AS_ERROR | Where-Object { $_ }) ?? $DefaultWarnAsError
$RulesetPath = ($RulesetPath | Where-Object { $_ }) ?? ($env:RULESET_PATH | Where-Object { $_ }) ?? $DefaultRulesetPath
$ServerUrl = ($ServerUrl | Where-Object { $_ }) ?? ($env:ALBT_BC_SERVER_URL | Where-Object { $_ }) ?? $DefaultServerUrl
$ServerInstance = ($ServerInstance | Where-Object { $_ }) ?? ($env:ALBT_BC_SERVER_INSTANCE | Where-Object { $_ }) ?? $DefaultServerInstance
$ContainerName = ($ContainerName | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_NAME | Where-Object { $_ }) ?? $DefaultContainerName
$ContainerUsername = ($ContainerUsername | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_USERNAME | Where-Object { $_ }) ?? $DefaultContainerUsername
$ContainerPassword = ($ContainerPassword | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_PASSWORD | Where-Object { $_ }) ?? $DefaultContainerPassword
$ContainerAuth = ($ContainerAuth | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_AUTH | Where-Object { $_ }) ?? $DefaultContainerAuth
$ArtifactCountry = ($ArtifactCountry | Where-Object { $_ }) ?? ($env:ALBT_BC_ARTIFACT_COUNTRY | Where-Object { $_ }) ?? $DefaultArtifactCountry
$ArtifactSelect = ($ArtifactSelect | Where-Object { $_ }) ?? ($env:ALBT_BC_ARTIFACT_SELECT | Where-Object { $_ }) ?? $DefaultArtifactSelect
$Tenant = ($Tenant | Where-Object { $_ }) ?? ($env:ALBT_BC_TENANT | Where-Object { $_ }) ?? $DefaultTenant
$ValidateCurrent = ($ValidateCurrent | Where-Object { $_ }) ?? ($env:ALBT_VALIDATE_CURRENT | Where-Object { $_ }) ?? $DefaultValidateCurrent

# =============================================================================
# Environment Configuration for Scripts
# =============================================================================

# Set environment variables for scripts (matching Makefile behavior)
# Always exported (like Makefile export statements)
$env:ALBT_APP_DIR = $AppDir
$env:ALBT_TEST_DIR = $TestDir
$env:WARN_AS_ERROR = $WarnAsError
$env:RULESET_PATH = $RulesetPath
$env:ALBT_BC_SERVER_URL = $ServerUrl
$env:ALBT_BC_SERVER_INSTANCE = $ServerInstance
$env:ALBT_BC_CONTAINER_NAME = $ContainerName
$env:ALBT_BC_CONTAINER_USERNAME = $ContainerUsername
$env:ALBT_BC_CONTAINER_PASSWORD = $ContainerPassword
$env:ALBT_BC_CONTAINER_AUTH = $ContainerAuth
$env:ALBT_BC_ARTIFACT_COUNTRY = $ArtifactCountry
$env:ALBT_BC_ARTIFACT_SELECT = $ArtifactSelect
$env:ALBT_BC_TENANT = $Tenant
$env:ALBT_VALIDATE_CURRENT = $ValidateCurrent

# PowerShell invocation settings (cross-platform compatible)
$ScriptCmd = @('pwsh', '-NoLogo', '-NoProfile', '-Command')

# =============================================================================
# Import Shared Utilities
# =============================================================================

# Load common helper functions used across build scripts
# This eliminates code duplication and provides a single source of truth
Import-Module "$PSScriptRoot/scripts/common.psm1" -Force -DisableNameChecking

# =============================================================================
# Helper Functions
# =============================================================================

function Invoke-BuildScript {
    param(
        [string]$ScriptName,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path 'scripts' 'make' $ScriptName
    if (-not (Test-Path $scriptPath)) {
        throw "Build script not found: $scriptPath"
    }

    # Set guard environment variable
    $env:ALBT_VIA_MAKE = "1"

    try {
        # Build command string for -Command parameter
        # Handle switches (arguments starting with -) differently from regular arguments
        $commandString = "& '$scriptPath'"
        foreach ($arg in $Arguments) {
            if ($arg -match '^-\w+$') {
                # Switch parameter - don't quote
                $commandString += " $arg"
            } else {
                # Regular argument - quote it
                $commandString += " '$arg'"
            }
        }
        $allArgs = $ScriptCmd + $commandString
        Write-Verbose "Executing: $($allArgs -join ' ')"

        & $allArgs[0] $allArgs[1..($allArgs.Count-1)]

        if ($LASTEXITCODE -ne 0) {
            throw "Script $ScriptName failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        # Clean up guard variable
        Remove-Item Env:ALBT_VIA_MAKE -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Task Definitions
# =============================================================================

# Synopsis: Show available tasks and usage information
task help {
    Write-TaskHeader "HELP" "AL Project Build System"

    Write-BuildMessage -Type Info -Message "AVAILABLE TASKS:"
    Write-BuildMessage -Type Detail -Message "download-compiler - Install/update the AL compiler dotnet tool"
    Write-BuildMessage -Type Detail -Message "download-symbols  - Download required Business Central symbol packages"
    Write-BuildMessage -Type Detail -Message "build             - Compile the AL project (requires provisioning first)"
    Write-BuildMessage -Type Detail -Message "clean             - Remove build artifacts"
    Write-BuildMessage -Type Detail -Message "show-config       - Display current configuration"
    Write-BuildMessage -Type Detail -Message "show-analyzers    - Show discovered analyzers"
    Write-BuildMessage -Type Detail -Message "provision         - Run full provisioning (compiler + symbols)"
    Write-BuildMessage -Type Detail -Message "help              - Show this help message"

    Write-BuildHeader 'Configuration Options'
    Write-BuildMessage -Type Detail -Message "WarnAsError=$WarnAsError - Treat warnings as errors (/warnaserror+)"
    Write-BuildMessage -Type Detail -Message "RulesetPath=$RulesetPath - Optional ruleset file passed to ALC if present"

    Write-BuildHeader 'Getting Started'
    Write-BuildMessage -Type Step -Message "Daily workflow: Invoke-Build (just builds)"
    Write-BuildMessage -Type Step -Message "New environment: First run 'Invoke-Build provision', then 'Invoke-Build'"
    Write-BuildMessage -Type Step -Message "Complete setup: Invoke-Build all (provision + build)"

    Write-BuildHeader 'Additional Commands'
    Write-BuildMessage -Type Detail -Message "Invoke-Build ?                    - Show all tasks with synopses"
    Write-BuildMessage -Type Detail -Message "Invoke-Build <task> -Verbose      - Run with verbose output"
    Write-BuildMessage -Type Detail -Message "Invoke-Build build -WarnAsError 0 - Run build allowing warnings"
}

# Synopsis: Install/update the AL compiler dotnet tool
task download-compiler {
    Write-TaskHeader "DOWNLOAD-COMPILER" "AL Compiler Provisioning"
    Invoke-BuildScript 'download-compiler.ps1'
}

# Synopsis: Download required Business Central symbol packages
task download-symbols {
    Write-TaskHeader "DOWNLOAD-SYMBOLS" "Symbol Package Provisioning"
    Invoke-BuildScript 'download-symbols.ps1' @($AppDir)
}

# Synopsis: Compile the AL project with analysis (requires provisioning first)
task build {
    Write-TaskHeader "BUILD" "AL Project Compilation"
    Invoke-BuildScript 'build.ps1' @($AppDir)
}

# Synopsis: Remove build artifacts
task clean {
    Write-TaskHeader "CLEAN" "Build Artifact Cleanup"
    Invoke-BuildScript 'clean.ps1' @($AppDir)
    Invoke-BuildScript 'clean.ps1' @($TestDir)
}

# Synopsis: Display current configuration
task show-config {
    Write-TaskHeader "SHOW-CONFIG" "Configuration Display"
    Invoke-BuildScript 'show-config.ps1' @($AppDir, $TestDir)
}

# Synopsis: Show discovered analyzers
task show-analyzers {
    Write-TaskHeader "SHOW-ANALYZERS" "Analyzer Discovery"
    Invoke-BuildScript 'show-analyzers.ps1' @($AppDir, $TestDir)
}

# Synopsis: Download symbols for test app
task download-symbols-test {
    Write-TaskHeader "DOWNLOAD-SYMBOLS-TEST" "Test App Symbol Provisioning"
    Invoke-BuildScript 'download-symbols.ps1' @($TestDir)
}

# Synopsis: Provision freshly-built main app as symbol for test app
task provision-test-dependencies build, {
    Write-TaskHeader "PROVISION-TEST-DEPENDENCIES" "Local Symbol Provisioning"
    Invoke-BuildScript 'provision-local-symbols.ps1' @($AppDir, $TestDir)
}

# Synopsis: Compile the test app
task build-test provision-test-dependencies, {
    Write-TaskHeader "BUILD-TEST" "Test App Compilation"
    # Allow warnings for test app (don't treat as errors)
    $savedWarnAsError = $env:WARN_AS_ERROR
    try {
        $env:WARN_AS_ERROR = "0"
        Invoke-BuildScript 'build.ps1' @($TestDir)
    } finally {
        $env:WARN_AS_ERROR = $savedWarnAsError
    }
}

# Synopsis: Publish main app to BC server
task publish build, {
    Write-TaskHeader "PUBLISH" "Main App Publishing"
    Invoke-BuildScript 'publish-app.ps1' @($AppDir, $ServerUrl, $ServerInstance)
}

# Synopsis: Publish test app to BC server
task publish-test build-test, {
    Write-TaskHeader "PUBLISH-TEST" "Test App Publishing"
    Invoke-BuildScript 'publish-app.ps1' @($TestDir, $ServerUrl, $ServerInstance)
}

# Synopsis: Run AL tests (builds, publishes, and executes tests)
task test build, build-test, publish, publish-test, {
    Write-TaskHeader "TEST" "AL Test Execution"
    Invoke-BuildScript 'run-tests.ps1' @($TestDir, $null, $null, $ServerUrl, $ServerInstance)
}

# Synopsis: Create and configure BC Docker container
task new-bc-container {
    Write-TaskHeader "NEW-BC-CONTAINER" "BC Docker Container Setup"
    Invoke-BuildScript 'new-bc-container.ps1'
}

# Synopsis: Validate app against previous release for breaking changes
task validate-breaking-changes build, {
    Write-TaskHeader "VALIDATE-BREAKING-CHANGES" "AL Breaking Change Validation"
    Invoke-BuildScript 'validate-breaking-changes.ps1' @($AppDir)
}

# Synopsis: Run full provisioning (compiler + symbols for main and test apps)
task provision download-compiler, download-symbols, download-symbols-test

# Synopsis: Default task - run tests (builds first via dependency)
task . test

# Synopsis: Full setup - provision and test (for new environments)
task all provision, test

# =============================================================================
# Task Validation
# =============================================================================

# Validate AppDir parameter
if ($AppDir -and -not (Test-Path $AppDir -PathType Container)) {
    Write-Warning "AppDir '$AppDir' does not exist or is not a directory"
}

# Show current configuration
Write-BuildHeader 'Build Configuration'
Write-BuildMessage -Type Detail -Message "AppDir: $AppDir"
Write-BuildMessage -Type Detail -Message "TestDir: $TestDir"
Write-BuildMessage -Type Detail -Message "WarnAsError: $WarnAsError"
Write-BuildMessage -Type Detail -Message "RulesetPath: $RulesetPath"
Write-BuildMessage -Type Detail -Message "ServerUrl: $ServerUrl"
Write-BuildMessage -Type Detail -Message "ServerInstance: $ServerInstance"
Write-BuildMessage -Type Detail -Message "ContainerName: $ContainerName"
Write-BuildMessage -Type Detail -Message "Tenant: $Tenant"
Write-BuildMessage -Type Detail -Message "ValidateCurrent: $ValidateCurrent"