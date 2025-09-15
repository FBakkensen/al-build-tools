#requires -Version 7.2

# Windows Clean Script
# Inlined helpers (formerly from lib/) to make this entrypoint self-contained.
param([string]$AppDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Verbosity (from common.ps1) ---
try {
    $v = $env:VERBOSE
    if ($v -and ($v -eq '1' -or $v -match '^(?i:true|yes|on)$')) { $VerbosePreference = 'Continue' }
    if ($VerbosePreference -eq 'Continue') { Write-Verbose '[albt] verbose mode enabled' }
} catch { }

# --- Exit codes (from common.ps1) ---
function Get-ExitCodes {
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

$Exit = Get-ExitCodes

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make clean)"
    exit $Exit.Guard
}

$outputPath = Get-OutputPath $AppDir
if ($outputPath -and (Test-Path $outputPath)) {
    Remove-Item -Force $outputPath
    Write-Output "Removed build artifact: $outputPath"
    exit $Exit.Success
} else {
    Write-Output "No build artifact found to clean ($outputPath)"
    exit $Exit.Success
}
