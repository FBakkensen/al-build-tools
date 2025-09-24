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

.PARAMETER LinterCopForce
    Force re-download of BusinessCentral.LinterCop analyzer (0/1, default: 0)

.PARAMETER SymbolCacheRoot
    Override symbol cache root path (default: ~/.bc-symbol-cache)

.PARAMETER SymbolFeeds
    Comma-separated feeds for symbol provisioning

.PARAMETER AlToolVersion
    Override compiler tool version when provisioning

.EXAMPLE
    Invoke-Build
    Runs the default 'build' task with all dependencies

.EXAMPLE
    Invoke-Build download-compiler -AlToolVersion "11.0.0"
    Download specific AL compiler version

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
    [ValidateSet("0", "1")]
    [string]$WarnAsError,
    [string]$RulesetPath,
    [ValidateSet("0", "1")]
    [string]$LinterCopForce,
    [string]$SymbolCacheRoot,
    [string]$SymbolFeeds,
    [string]$AlToolVersion
)

# =============================================================================
# Project Configuration (tweak as needed when bootstrapping)
# =============================================================================
# Directory containing the AL project files and app.json
$DefaultAppDir = "."

# Build Options
$DefaultWarnAsError = "1"                    # Treat AL compiler warnings as errors (1 to enable, 0 to disable)
$DefaultRulesetPath = "al.ruleset.json"      # Optional ruleset file for analyzers (leave empty to disable)
$DefaultLinterCopForce = "0"                 # Force re-download of BusinessCentral.LinterCop analyzer (0/1)

# Provisioning Options (override via environment or parameters)
$DefaultSymbolCacheRoot = ""                 # Override symbol cache root path (empty = use default ~/.bc-symbol-cache)
$DefaultSymbolFeeds = ""                     # Comma-separated feeds for symbol provisioning
$DefaultAlToolVersion = ""                   # Override compiler tool version when provisioning

# =============================================================================
# Three-Tier Configuration Resolution using PowerShell 7+ coalescing operators
# Priority: 1. Parameter → 2. Environment Variable → 3. File Setting
# =============================================================================

# Elegant configuration resolution using null coalescing operator (??)
# Each ?? moves to the next value if the previous is null or empty
$AppDir = ($AppDir | Where-Object { $_ }) ?? ($env:ALBT_APP_DIR | Where-Object { $_ }) ?? $DefaultAppDir
$WarnAsError = ($WarnAsError | Where-Object { $_ }) ?? ($env:WARN_AS_ERROR | Where-Object { $_ }) ?? $DefaultWarnAsError
$RulesetPath = ($RulesetPath | Where-Object { $_ }) ?? ($env:RULESET_PATH | Where-Object { $_ }) ?? $DefaultRulesetPath
$LinterCopForce = ($LinterCopForce | Where-Object { $_ }) ?? ($env:ALBT_FORCE_LINTERCOP | Where-Object { $_ }) ?? $DefaultLinterCopForce
$SymbolCacheRoot = ($SymbolCacheRoot | Where-Object { $_ }) ?? ($env:ALBT_SYMBOL_CACHE_ROOT | Where-Object { $_ }) ?? $DefaultSymbolCacheRoot
$SymbolFeeds = ($SymbolFeeds | Where-Object { $_ }) ?? ($env:ALBT_SYMBOL_FEEDS | Where-Object { $_ }) ?? $DefaultSymbolFeeds
$AlToolVersion = ($AlToolVersion | Where-Object { $_ }) ?? ($env:AL_TOOL_VERSION | Where-Object { $_ }) ?? $DefaultAlToolVersion# =============================================================================
# Environment Configuration for Scripts
# =============================================================================

# Set environment variables for scripts (matching Makefile behavior)
# Always exported (like Makefile export statements)
$env:WARN_AS_ERROR = $WarnAsError
$env:RULESET_PATH = $RulesetPath
$env:ALBT_FORCE_LINTERCOP = $LinterCopForce

# Conditionally exported (only if they have values, like Makefile ifdef statements)
if ($SymbolCacheRoot) { $env:ALBT_SYMBOL_CACHE_ROOT = $SymbolCacheRoot }
if ($SymbolFeeds) { $env:ALBT_SYMBOL_FEEDS = $SymbolFeeds }
if ($AlToolVersion) { $env:AL_TOOL_VERSION = $AlToolVersion }

# PowerShell invocation settings (cross-platform compatible)
$ScriptCmd = @('pwsh', '-NoLogo', '-NoProfile', '-Command')

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
        $commandString = "& '$scriptPath'" + ($Arguments | ForEach-Object { " '$_'" })
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

function Write-TaskHeader {
    param([string]$TaskName, [string]$Description)

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "🔧 INVOKE-BUILD | $TaskName | $Description" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Task Definitions
# =============================================================================

# Synopsis: Show available tasks and usage information
task help {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "🔧 INVOKE-BUILD | AL Project Build System | PowerShell Only" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📋 AVAILABLE TASKS:" -ForegroundColor Cyan
    Write-Host "  • download-compiler - Install/update the AL compiler dotnet tool" -ForegroundColor White
    Write-Host "  • download-symbols  - Download required Business Central symbol packages" -ForegroundColor White
    Write-Host "  • build             - Compile the AL project (requires provisioning first)" -ForegroundColor White
    Write-Host "  • clean             - Remove build artifacts" -ForegroundColor White
    Write-Host "  • show-config       - Display current configuration" -ForegroundColor White
    Write-Host "  • show-analyzers    - Show discovered analyzers" -ForegroundColor White
    Write-Host "  • provision         - Run full provisioning (compiler + symbols)" -ForegroundColor White
    Write-Host "  • help              - Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "⚙️  CONFIGURATION OPTIONS:" -ForegroundColor Cyan
    Write-Host "  WarnAsError=$WarnAsError         Treat warnings as errors (/warnaserror+)" -ForegroundColor White
    Write-Host "  RulesetPath=$RulesetPath   Optional ruleset file passed to ALC if present" -ForegroundColor White
    if ($AlToolVersion) {
        Write-Host "  AlToolVersion=$AlToolVersion         Override compiler tool version when provisioning" -ForegroundColor White
    }
    if ($SymbolCacheRoot) {
        Write-Host "  SymbolCacheRoot=$SymbolCacheRoot  Override symbol cache root path" -ForegroundColor White
    }
    if ($SymbolFeeds) {
        Write-Host "  SymbolFeeds=$SymbolFeeds      Comma-separated feeds for symbol provisioning" -ForegroundColor White
    }
    Write-Host "  LinterCopForce=$LinterCopForce         Force re-download of BusinessCentral.LinterCop analyzer (1=yes)" -ForegroundColor White
    Write-Host ""
    Write-Host "🚀 GETTING STARTED:" -ForegroundColor Cyan
    Write-Host "  ✓ Daily workflow: Invoke-Build (just builds)" -ForegroundColor White
    Write-Host "  ✓ New environment: First run 'Invoke-Build provision', then 'Invoke-Build'" -ForegroundColor White
    Write-Host "  ✓ Complete setup: Invoke-Build all (provision + build)" -ForegroundColor White
    Write-Host ""
    Write-Host "📖 ADDITIONAL COMMANDS:" -ForegroundColor Cyan
    Write-Host "  Invoke-Build ?                    Show all tasks with synopses" -ForegroundColor White
    Write-Host "  Invoke-Build <task> -Verbose      Run with verbose output" -ForegroundColor White
    Write-Host "  Invoke-Build build -WarnAsError 0 Run build allowing warnings" -ForegroundColor White
    Write-Host ""
}

# Synopsis: Install/update the AL compiler dotnet tool
task download-compiler {
    Write-TaskHeader "DOWNLOAD-COMPILER" "AL Compiler Provisioning"
    Invoke-BuildScript 'download-compiler.ps1' @($AppDir)
}

# Synopsis: Download required Business Central symbol packages
task download-symbols {
    Write-TaskHeader "DOWNLOAD-SYMBOLS" "Symbol Package Provisioning"
    Invoke-BuildScript 'download-symbols.ps1' @($AppDir, '-VerboseSymbols')
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
}

# Synopsis: Display current configuration
task show-config {
    Write-TaskHeader "SHOW-CONFIG" "Configuration Display"
    Invoke-BuildScript 'show-config.ps1' @($AppDir)
}

# Synopsis: Show discovered analyzers
task show-analyzers {
    Write-TaskHeader "SHOW-ANALYZERS" "Analyzer Discovery"
    Invoke-BuildScript 'show-analyzers.ps1' @($AppDir)
}

# Synopsis: Run full provisioning (compiler + symbols)
task provision download-compiler, download-symbols

# Synopsis: Default task - build the AL project
task . build

# Synopsis: Full setup - provision and build (for new environments)
task all provision, build

# =============================================================================
# Task Validation
# =============================================================================

# Validate AppDir parameter
if ($AppDir -and -not (Test-Path $AppDir -PathType Container)) {
    Write-Warning "AppDir '$AppDir' does not exist or is not a directory"
}

# Show current configuration when running with -Verbose
if ($VerbosePreference -eq 'Continue') {
    Write-Host "🔧 Build Configuration:" -ForegroundColor Cyan
    Write-Host "  AppDir: $AppDir" -ForegroundColor White
    Write-Host "  WarnAsError: $WarnAsError" -ForegroundColor White
    Write-Host "  RulesetPath: $RulesetPath" -ForegroundColor White
    Write-Host "  LinterCopForce: $LinterCopForce" -ForegroundColor White
    if ($AlToolVersion) { Write-Host "  AlToolVersion: $AlToolVersion" -ForegroundColor White }
    if ($SymbolCacheRoot) { Write-Host "  SymbolCacheRoot: $SymbolCacheRoot" -ForegroundColor White }
    if ($SymbolFeeds) { Write-Host "  SymbolFeeds: $SymbolFeeds" -ForegroundColor White }
    Write-Host ""
}