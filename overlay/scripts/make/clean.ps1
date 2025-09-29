#requires -Version 7.2

<#
.SYNOPSIS
    Clean AL project build artifacts with structured status reporting.

.DESCRIPTION
    Removes generated .app build artifacts from the AL project directory and provides
    detailed status information about the cleanup operation.

.PARAMETER AppDir
    Directory containing app.json and build artifacts (defaults to current directory)

.NOTES
    This script uses Write-Information for output to ensure compatibility with different
    PowerShell hosts and automation scenarios.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param([string]$AppDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# --- Verbosity (from common.ps1) ---
try {
    $v = $env:VERBOSE
    if ($v -and ($v -eq '1' -or $v -match '^(?i:true|yes|on)$')) { $VerbosePreference = 'Continue' }
    if ($VerbosePreference -eq 'Continue') { Write-Verbose '[albt] verbose mode enabled' }
} catch {
    Write-Verbose "[albt] verbose env check failed: $($_.Exception.Message)"
}

# --- Exit codes (from common.ps1) ---
function Get-ExitCode {
    return @{
        Success      = 0
        GeneralError = 1
        Guard        = 2
        Analysis     = 3
        Contract     = 4
        Integration  = 5
        MissingTool  = 6
    }
}

# --- Formatting Helpers ---
function Write-Section {
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 CLEAN | {0}" -f $Title
    if ($SubInfo) { $header += " | {0}" -f $SubInfo }
    Write-Information $header -InformationAction Continue
    Write-Information $line -InformationAction Continue
}

function Write-InfoLine {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Icon = '•'
    )
    $labelPadded = ($Label).PadRight(12)
    Write-Information ("  {0}{1}: {2}" -f $Icon, $labelPadded, $Value) -InformationAction Continue
}

function Write-StatusLine {
    param([string]$Message, [string]$Icon = '⚠️')
    Write-Information ("  {0} {1}" -f $Icon, $Message) -InformationAction Continue
}

# --- Path helpers (from common.ps1) ---
function Get-AppJsonPath { param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath 'app.json'
    $p2 = 'app.json'
    if (Test-Path $p1) { return $p1 } elseif (Test-Path $p2) { return $p2 } else { return $null }
}
function Get-OutputPath { param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try {
        $json = Get-Content $appJson -Raw | ConvertFrom-Json
        $name = if ($json.name) { $json.name } else { 'CopilotAllTablesAndFields' }
        $version = if ($json.version) { $json.version } else { '1.0.0.0' }
        $publisher = if ($json.publisher) { $json.publisher } else { 'FBakkensen' }
        $file = "${publisher}_${name}_${version}.app"
        return Join-Path -Path $AppDir -ChildPath $file
    } catch { return $null }
}

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make clean)"
    exit $Exit.Guard
}

Write-Section 'Build Artifact Analysis'

$outputPath = Get-OutputPath $AppDir
$fileName = if ($outputPath) { Split-Path $outputPath -Leaf } else { '(unknown)' }
$directory = if ($outputPath) { Split-Path $outputPath -Parent } else { '(unknown)' }

Write-Information "📂 ARTIFACT DETECTION:" -InformationAction Continue
Write-InfoLine "Expected File" $fileName '📄'
Write-InfoLine "Target Dir" $directory '📁'

$artifactExists = $outputPath -and (Test-Path $outputPath)
if ($artifactExists) {
    Write-InfoLine "Status" "Found" '✅'
} else {
    Write-InfoLine "Status" "Not Found" '⚠️'
}

Write-Section 'Cleanup Operation'

if ($artifactExists) {
    Write-Information "🗑️ REMOVING ARTIFACTS:" -InformationAction Continue

    try {
        # Get file info before deletion for reporting
        $fileInfo = Get-Item -LiteralPath $outputPath
        $fileSize = if ($fileInfo.Length -lt 1024) {
            "{0} bytes" -f $fileInfo.Length
        } elseif ($fileInfo.Length -lt 1048576) {
            "{0:N1} KB" -f ($fileInfo.Length / 1024)
        } else {
            "{0:N1} MB" -f ($fileInfo.Length / 1048576)
        }

        Remove-Item -Force $outputPath -ErrorAction Stop
        Write-InfoLine "Operation" "Success" '✅'
        Write-InfoLine "Removed" $fileName '🗑️'
        Write-InfoLine "Size Freed" $fileSize '💾'
        Write-InfoLine "Path" $outputPath '📁'

        Write-Section 'Summary'
        Write-Information "✅ Cleanup completed successfully!" -InformationAction Continue
        Write-StatusLine "Build artifact removed successfully" '✅'

    } catch {
        Write-InfoLine "Operation" "Failed" '❌'
        Write-StatusLine "Error removing build artifact: $($_.Exception.Message)" '❌'
        exit $Exit.GeneralError
    }
} else {
    Write-Information "🔍 CLEANUP STATUS:" -InformationAction Continue
    Write-InfoLine "Operation" "Skipped" '⚠️'
    Write-InfoLine "Reason" "No artifacts found" '📋'
    if ($outputPath) {
        Write-InfoLine "Expected Path" $outputPath '📁'
    }

Write-Section 'Summary'
Write-Information "ℹ️ No cleanup needed - workspace is already clean!" -InformationAction Continue
Write-StatusLine "No build artifacts found to remove" 'ℹ️'
}

# --- Enhanced Cache Cleanup Options ---
Write-Section 'Cache Cleanup Options' 'Manual Operations'

Write-Information "🧹 MANUAL CACHE CLEANUP COMMANDS:" -InformationAction Continue
Write-Information "   Use these commands for advanced cache management:" -InformationAction Continue
Write-Information "" -InformationAction Continue

$userHome = $env:HOME
if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }

if ($userHome) {
    $cacheRoot = Join-Path $userHome '.bc-tool-cache'
    $alCacheRoot = Join-Path $cacheRoot 'al'

    Write-Information "🗂️  COMPILER CACHE CLEANUP:" -InformationAction Continue
    Write-Information ("   • Clean all compiler versions:") -InformationAction Continue
    Write-Information ("     Remove-Item '{0}' -Recurse -Force -ErrorAction SilentlyContinue" -f $alCacheRoot) -InformationAction Continue
    Write-Information ("   • Clean specific runtime cache (e.g., runtime 15):") -InformationAction Continue
    Write-Information ("     Remove-Item '{0}' -Recurse -Force -ErrorAction SilentlyContinue" -f (Join-Path $alCacheRoot 'runtime-15')) -InformationAction Continue
    Write-Information ("   • Clean legacy cache only:") -InformationAction Continue
    Write-Information ("     Remove-Item '{0}' -Force -ErrorAction SilentlyContinue" -f (Join-Path $alCacheRoot 'default.json')) -InformationAction Continue
    Write-Information "" -InformationAction Continue

    $symbolCacheRoot = Join-Path $userHome '.bc-symbol-cache'
    Write-Information "📦 SYMBOL CACHE CLEANUP:" -InformationAction Continue
    Write-Information ("   • Clean all symbol packages:") -InformationAction Continue
    Write-Information ("     Remove-Item '{0}' -Recurse -Force -ErrorAction SilentlyContinue" -f $symbolCacheRoot) -InformationAction Continue
    Write-Information "" -InformationAction Continue

    Write-Information "🔄 CACHE RESET COMMANDS:" -InformationAction Continue
    Write-Information ("   • Complete cache reset (compiler + symbols):") -InformationAction Continue
    Write-Information ("     Remove-Item '{0}', '{1}' -Recurse -Force -ErrorAction SilentlyContinue" -f $alCacheRoot, $symbolCacheRoot) -InformationAction Continue
    Write-Information ("   • Reprovision after cleanup:") -InformationAction Continue
    Write-Information ("     Invoke-Build provision") -InformationAction Continue
    Write-Information "" -InformationAction Continue

    Write-Information "⚙️  CACHE DIAGNOSTICS:" -InformationAction Continue
    Write-Information ("   • Show cache disk usage:") -InformationAction Continue
    Write-Information ("     Get-ChildItem '{0}' -Recurse | Measure-Object -Property Length -Sum" -f $cacheRoot) -InformationAction Continue
    Write-Information ("   • List runtime-specific caches:") -InformationAction Continue
    Write-Information ("     Get-ChildItem '{0}' -Directory -Filter 'runtime-*'" -f $alCacheRoot) -InformationAction Continue
    Write-Information ("   • Show current configuration:") -InformationAction Continue
    Write-Information ("     Invoke-Build show-config") -InformationAction Continue
} else {
    Write-StatusLine "Unable to determine cache paths (HOME directory not found)" '⚠️'
}

Write-Information "" -InformationAction Continue
Write-StatusLine "Use cache cleanup commands only when necessary" 'ℹ️'
Write-StatusLine "Cache improves build performance - clean only for troubleshooting" 'ℹ️'

exit $Exit.Success