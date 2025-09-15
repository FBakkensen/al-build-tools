#requires -Version 7.2

# Windows Show-Config Script
# Inlined helpers (formerly from lib/) to make this entrypoint self-contained.
param([string]$AppDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Verbosity (from common.ps1) ---
try {
    $v = $env:VERBOSE
    if ($v -and ($v -eq '1' -or $v -match '^(?i:true|yes|on)$')) { $VerbosePreference = 'Continue' }
    if ($VerbosePreference -eq 'Continue') { Write-Verbose '[albt] verbose mode enabled' }
} catch {
    Write-Verbose "[albt] verbose env check failed: $($_.Exception.Message)"
}

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

# --- Paths and JSON helpers (from common.ps1/json-parser.ps1) ---
function Get-AppJsonPath { param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath 'app.json'
    $p2 = 'app.json'
    if (Test-Path $p1) { return $p1 } elseif (Test-Path $p2) { return $p2 } else { return $null }
}
function Get-SettingsJsonPath { param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath '.vscode/settings.json'
    if (Test-Path $p1) { return $p1 }
    $p2 = '.vscode/settings.json'
    if (Test-Path $p2) { return $p2 }
    return $null
}
function Get-AppJsonObject { param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try { Get-Content $appJson -Raw | ConvertFrom-Json } catch { $null }
}
function Get-SettingsJsonObject { param([string]$AppDir)
    $path = Get-SettingsJsonPath $AppDir
    if (-not $path) { return $null }
    try { Get-Content $path -Raw | ConvertFrom-Json } catch { $null }
}

$Exit = Get-ExitCodes

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make show-config)"
    exit $Exit.Guard
}

$appJson = Get-AppJsonObject $AppDir
if ($appJson) {
    Write-Output "App.json configuration:"
    Write-Output "  Name: $($appJson.name)"
    Write-Output "  Publisher: $($appJson.publisher)"
    Write-Output "  Version: $($appJson.version)"
} else {
    Write-Error -ErrorAction Continue "ERROR: app.json not found or invalid."
}

$settingsJson = Get-SettingsJsonObject $AppDir
if ($settingsJson) {
    Write-Output "Settings.json configuration:"
    if (($settingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        Write-Output "  Analyzers: $($settingsJson.'al.codeAnalyzers')"
    } else {
        Write-Output "  Analyzers: (none)"
    }
} else {
    Write-Warning ".vscode/settings.json not found or invalid."
}

# Normalized deterministic key=value section (T010)
# This block is additive to keep backward compatibility with existing consumers/tests.
try {
    $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } elseif ($IsLinux) { 'Linux' } else { ($PSVersionTable.Platform ?? 'Unknown') }
} catch { $platform = 'Unknown' }

$psver = try { $PSVersionTable.PSVersion.ToString() } catch { ($PSVersionTable.PSVersion.Major.ToString()) }

$appName = if ($appJson) { "$($appJson.name)" } else { '(missing)' }
$appPublisher = if ($appJson) { "$($appJson.publisher)" } else { '(missing)' }
$appVersion = if ($appJson) { "$($appJson.version)" } else { '(missing)' }

$analyzersList = '(none)'
if ($settingsJson) {
    if (($settingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        $analyzersList = ($settingsJson.'al.codeAnalyzers' | ForEach-Object { $_.ToString() }) -join ', '
    } else {
        $analyzersList = '(none)'
    }
} else {
    # Treat missing settings as no analyzers configured for normalized view
    $analyzersList = '(none)'
}

# Emit in fixed, deterministic order
$normalized = [ordered]@{
    'App.Name'           = $appName
    'App.Publisher'      = $appPublisher
    'App.Version'        = $appVersion
    'Platform'           = $platform
    'PowerShellVersion'  = $psver
    'Settings.Analyzers' = $analyzersList
}

foreach ($k in $normalized.Keys) {
    Write-Output ("{0}={1}" -f $k, $normalized[$k])
}
exit $Exit.Success
