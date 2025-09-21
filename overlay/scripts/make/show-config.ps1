#requires -Version 7.2

<#
.SYNOPSIS
    Display comprehensive AL project configuration information with structured formatting.

.DESCRIPTION
    Shows application configuration, compiler status, symbol cache status, and environment
    details in a structured format suitable for both interactive display and automation.

.PARAMETER AppDir
    Directory containing app.json (defaults to current directory)

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

# --- Provisioning helpers ---
function Expand-FullPath {
    param([string]$Path)

    if (-not $Path) { return $null }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)

    if ($expanded.StartsWith('~')) {
        $userHome = $env:HOME
        if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
        if ($userHome) {
            $suffix = $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if ([string]::IsNullOrWhiteSpace($suffix)) {
                $expanded = $userHome
            } else {
                $expanded = Join-Path -Path $userHome -ChildPath $suffix
            }
        }
    }

    try {
        return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).ProviderPath
    } catch {
        return [System.IO.Path]::GetFullPath($expanded)
    }
}

function Get-ToolCacheRoot {
    $override = $env:ALBT_TOOL_CACHE_ROOT
    if ($override) { return Expand-FullPath -Path $override }

    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to determine home directory for tool cache. Set ALBT_TOOL_CACHE_ROOT or rerun provisioning.' }

    return Join-Path -Path $userHome -ChildPath '.bc-tool-cache'
}

function Get-CompilerProvisioningInfo {
    param([string]$ToolVersion)

    $toolCacheRoot = Get-ToolCacheRoot
    $alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
    $sentinelName = if ($ToolVersion) { "$ToolVersion.json" } else { 'default.json' }
    $sentinelPath = Join-Path -Path $alCacheDir -ChildPath $sentinelName

    if (-not (Test-Path -LiteralPath $sentinelPath)) {
        throw "Compiler provisioning sentinel not found at $sentinelPath. Run `make download-compiler` before inspecting configuration."
    }

    try {
        $sentinel = Get-Content -LiteralPath $sentinelPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse compiler sentinel at ${sentinelPath}: $($_.Exception.Message). Run `make download-compiler` before inspecting configuration."
    }

    $toolPath = if ($sentinel) { [string]$sentinel.toolPath } else { $null }
    if (-not $toolPath) {
        throw "Compiler sentinel at $sentinelPath missing toolPath. Run `make download-compiler` before inspecting configuration."
    }

    $resolvedToolPath = Expand-FullPath -Path $toolPath
    if (-not (Test-Path -LiteralPath $resolvedToolPath)) {
        throw "AL compiler not found at ${resolvedToolPath} (sentinel ${sentinelPath}). Run `make download-compiler` before inspecting configuration."
    }

    $toolItem = Get-Item -LiteralPath $resolvedToolPath
    $compilerVersion = if ($sentinel.PSObject.Properties.Match('compilerVersion').Count -gt 0) { [string]$sentinel.compilerVersion } else { $null }

    return [pscustomobject]@{
        AlcPath      = $toolItem.FullName
        Version      = $compilerVersion
        SentinelPath = $sentinelPath
    }
}

function ConvertTo-SafePathSegment {
    param([string]$Value)

    if (-not $Value) { return '_' }

    $invalid = [System.IO.Path]::GetInvalidFileNameChars() + [char]':'
    $result = $Value
    foreach ($char in $invalid) {
        $pattern = [regex]::Escape([string]$char)
        $result = $result -replace $pattern, '_'
    }
    $result = $result -replace '\s+', '_'
    if ([string]::IsNullOrWhiteSpace($result)) { return '_' }
    return $result
}

function Get-SymbolCacheRoot {
    $override = $env:ALBT_SYMBOL_CACHE_ROOT
    if ($override) { return Expand-FullPath -Path $override }

    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to determine home directory for symbol cache. Set ALBT_SYMBOL_CACHE_ROOT or rerun provisioning.' }

    return Join-Path -Path $userHome -ChildPath '.bc-symbol-cache'
}

function Get-SymbolCacheInfo {
    param($AppJson)

    if (-not $AppJson) {
        throw 'app.json is required to resolve the symbol cache. Ensure app.json exists and run `make download-symbols`.'
    }

    if (-not $AppJson.publisher) {
        throw 'app.json missing "publisher". Update the manifest and rerun `make download-symbols`.'
    }
    if (-not $AppJson.name) {
        throw 'app.json missing "name". Update the manifest and rerun `make download-symbols`.'
    }
    if (-not $AppJson.id) {
        throw 'app.json missing "id". Update the manifest and rerun `make download-symbols`.'
    }

    $cacheRoot = Get-SymbolCacheRoot

    $publisherDir = Join-Path -Path $cacheRoot -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.publisher)
    $appDirPath = Join-Path -Path $publisherDir -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.name)
    $cacheDir = Join-Path -Path $appDirPath -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.id)

    if (-not (Test-Path -LiteralPath $cacheDir)) {
        throw "Symbol cache directory not found at $cacheDir. Run `make download-symbols` before inspecting configuration."
    }

    $manifestPath = Join-Path -Path $cacheDir -ChildPath 'symbols.lock.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Symbol manifest missing at $manifestPath. Run `make download-symbols` before inspecting configuration."
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse symbol manifest at ${manifestPath}: $($_.Exception.Message). Run `make download-symbols` before inspecting configuration."
    }

    return [pscustomobject]@{
        CacheDir     = (Get-Item -LiteralPath $cacheDir).FullName
        ManifestPath = $manifestPath
        Manifest     = $manifest
    }
}

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make show-config)"
    exit $Exit.Guard
}

# --- Formatting Helpers ---
function Write-Section {
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 CONFIG | {0}" -f $Title
    if ($SubInfo) { $header += " | {0}" -f $SubInfo }
    Write-Information $header -InformationAction Continue
    Write-Information $line -InformationAction Continue
}

function Write-ConfigLine {
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

Write-Section 'Application Configuration'

$appJson = Get-AppJsonObject $AppDir
if ($appJson) {
    Write-Information "📱 APPLICATION MANIFEST:" -InformationAction Continue
    Write-ConfigLine "Name" $appJson.name '✓'
    Write-ConfigLine "Publisher" $appJson.publisher '✓'
    Write-ConfigLine "Version" $appJson.version '✓'
} else {
    Write-StatusLine "app.json not found or invalid" '❌'
}

Write-Section 'VS Code Configuration'

$settingsJson = Get-SettingsJsonObject $AppDir
if ($settingsJson) {
    Write-Information "⚙️ VSCODE SETTINGS:" -InformationAction Continue
    if (($settingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        $analyzerCount = $settingsJson.'al.codeAnalyzers'.Count
        Write-ConfigLine "Analyzers" "$analyzerCount configured" '📊'
        foreach ($analyzer in $settingsJson.'al.codeAnalyzers') {
            Write-Information ("    → {0}" -f $analyzer) -InformationAction Continue
        }
    } else {
        Write-ConfigLine "Analyzers" "(none configured)" '📊'
    }
} else {
    Write-StatusLine ".vscode/settings.json not found or invalid" '⚠️'
}

$requestedToolVersion = $env:AL_TOOL_VERSION
$alcOverride = $env:ALBT_ALC_SHIM
if (-not $alcOverride -and $env:ALBT_ALC_PATH) { $alcOverride = $env:ALBT_ALC_PATH }

$compilerPathValue = '(missing)'
$compilerVersionValue = '(missing)'
$compilerSentinelValue = '(missing)'
$symbolCacheValue = '(missing)'
$symbolManifestValue = '(missing)'

$alcPath = $null
$compilerVersion = $null
$compilerSentinel = $null
$compilerWarning = $null

if ($alcOverride) {
    $resolvedOverride = Expand-FullPath -Path $alcOverride
    if (-not (Test-Path -LiteralPath $resolvedOverride)) {
        $compilerWarning = "AL compiler override not found at $alcOverride."
    } else {
        $alcPath = (Get-Item -LiteralPath $resolvedOverride).FullName
        $compilerVersion = '(override)'
    }
} elseif ($appJson) {
    try {
        $compilerInfo = Get-CompilerProvisioningInfo -ToolVersion $requestedToolVersion
        if ($compilerInfo) {
            $alcPath = $compilerInfo.AlcPath
            $compilerVersion = $compilerInfo.Version
            $compilerSentinel = $compilerInfo.SentinelPath
        }
    } catch {
        $compilerWarning = $_.Exception.Message
    }
}

Write-Section 'Compiler Provisioning'

if ($alcPath) {
    Write-Information "🔨 COMPILER STATUS:" -InformationAction Continue
    Write-ConfigLine "Status" "Ready" '✅'
    if ($compilerVersion) {
        Write-ConfigLine "Version" $compilerVersion '📦'
    } else {
        Write-ConfigLine "Version" "(unknown)" '📦'
    }
    Write-ConfigLine "Path" $alcPath '📁'
    if ($compilerSentinel) {
        Write-ConfigLine "Sentinel" $compilerSentinel '📋'
    }
    $compilerPathValue = $alcPath
    $compilerVersionValue = if ($compilerVersion) { $compilerVersion } else { '(unknown)' }
    $compilerSentinelValue = if ($compilerSentinel) { $compilerSentinel } else { '(missing)' }
} elseif ($compilerWarning) {
    Write-Information "🔨 COMPILER STATUS:" -InformationAction Continue
    Write-StatusLine $compilerWarning '❌'
} else {
    Write-Information "🔨 COMPILER STATUS:" -InformationAction Continue
    Write-StatusLine "Compiler provisioning info unavailable. Run 'make download-compiler' or set ALBT_ALC_PATH" '❌'
}

$symbolCacheInfo = $null
$symbolWarning = $null
if ($appJson) {
    try {
        $symbolCacheInfo = Get-SymbolCacheInfo -AppJson $appJson
    } catch {
        $symbolWarning = $_.Exception.Message
    }
}

Write-Section 'Symbol Cache Status'

if ($symbolCacheInfo) {
    Write-Information "📦 SYMBOLS STATUS:" -InformationAction Continue
    Write-ConfigLine "Status" "Ready" '✅'
    if ($symbolCacheInfo.Manifest -and $symbolCacheInfo.Manifest.packages) {
        $packageNode = $symbolCacheInfo.Manifest.packages
        $count = 0
        if ($packageNode -is [System.Collections.IDictionary]) {
            $count = $packageNode.Count
        } elseif ($packageNode.PSObject) {
            $count = @($packageNode.PSObject.Properties).Count
        }
        Write-ConfigLine "Packages" "$count cached" '📊'
    }
    Write-ConfigLine "Directory" $symbolCacheInfo.CacheDir '📁'
    Write-ConfigLine "Manifest" $symbolCacheInfo.ManifestPath '📋'
    $symbolCacheValue = $symbolCacheInfo.CacheDir
    $symbolManifestValue = $symbolCacheInfo.ManifestPath
} elseif ($symbolWarning) {
    Write-Information "📦 SYMBOLS STATUS:" -InformationAction Continue
    Write-StatusLine $symbolWarning '❌'
} elseif ($appJson) {
    Write-Information "📦 SYMBOLS STATUS:" -InformationAction Continue
    Write-StatusLine "Symbol cache info unavailable. Run 'make download-symbols'" '❌'
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

Write-Section 'System Environment'

Write-Information "🖥️ PLATFORM INFO:" -InformationAction Continue
Write-ConfigLine "Platform" $platform '🖥️'
Write-ConfigLine "PowerShell" $psver '⚡'

Write-Section 'Configuration Summary' 'Key-Value Export'

Write-Information "📋 NORMALIZED CONFIGURATION:" -InformationAction Continue
Write-Information "   Machine-readable format for integration and debugging:" -InformationAction Continue

# Emit in fixed, deterministic order
$normalized = [ordered]@{
    'App.Name'           = $appName
    'App.Publisher'      = $appPublisher
    'App.Version'        = $appVersion
    'Platform'           = $platform
    'PowerShellVersion'  = $psver
    'Settings.Analyzers' = $analyzersList
    'Compiler.Path'      = $compilerPathValue
    'Compiler.Version'   = $compilerVersionValue
    'Compiler.Sentinel'  = $compilerSentinelValue
    'Symbols.Cache'      = $symbolCacheValue
    'Symbols.Manifest'   = $symbolManifestValue
}

foreach ($k in $normalized.Keys) {
    $value = $normalized[$k]
    $displayValue = if ($value.Length -gt 80) { $value.Substring(0, 77) + "..." } else { $value }
    Write-Information ("   {0}={1}" -f $k, $displayValue) -InformationAction Continue
}

Write-Information "" -InformationAction Continue
Write-Information "✅ Configuration review complete!" -InformationAction Continue
exit $Exit.Success
