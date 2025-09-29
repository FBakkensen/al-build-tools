#requires -Version 7.2

<#
.SYNOPSIS
    Build AL project with comprehensive status reporting and modern terminal output.

.DESCRIPTION
    Compiles the AL project using the provisioned compiler and symbols, with detailed
    progress tracking, analyzer configuration, and structured error reporting.

.PARAMETER AppDir
    Directory containing the AL project files and app.json (defaults to "app")

.NOTES
    This script uses Write-Information for output to ensure compatibility with different
    PowerShell hosts and automation scenarios.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param([string]$AppDir = "app")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# --- Formatting Helpers ---
function Write-Section {
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 BUILD | {0}" -f $Title
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
    $labelPadded = ($Label).PadRight(14)
    Write-Information ("  {0}{1}: {2}" -f $Icon, $labelPadded, $Value) -InformationAction Continue
}

function Write-StatusLine {
    param([string]$Message, [string]$Icon = '⚠️')
    Write-Information ("  {0} {1}" -f $Icon, $Message) -InformationAction Continue
}

function Write-ListItem {
    param([string]$Item, [string]$Icon = '→')
    Write-Information ("    {0} {1}" -f $Icon, $Item) -InformationAction Continue
}

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
    if (-not $userHome) { throw 'Unable to determine home directory for tool cache.' }

    return Join-Path -Path $userHome -ChildPath '.bc-tool-cache'
}

function Get-RuntimeMajorVersion {
    <#
    .SYNOPSIS
        Extract major version from runtime version string
    .PARAMETER RuntimeVersion
        Runtime version string from app.json (e.g., "15.2", "16.0")
    .OUTPUTS
        String containing major version number or $null if invalid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$RuntimeVersion
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeVersion)) {
        return $null
    }

    # Extract major version from runtime (e.g., "15.2" -> "15")
    if ($RuntimeVersion -match '^(\d+)\.') {
        return $matches[1]
    }

    # Handle single digit versions like "15"
    if ($RuntimeVersion -match '^\d+$') {
        return $RuntimeVersion
    }

    return $null
}

function Get-CompilerProvisioningInfo {
    param(
        [string]$ToolVersion,
        [string]$RuntimeVersion
    )

    $toolCacheRoot = Get-ToolCacheRoot
    $alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'

    # Priority 1: Runtime-specific cache (new approach)
    if ($RuntimeVersion) {
        $majorVersion = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
        if ($majorVersion) {
            $runtimeCacheDir = Join-Path -Path $alCacheDir -ChildPath "runtime-$majorVersion"
            $runtimeSentinelPath = Join-Path -Path $runtimeCacheDir -ChildPath 'sentinel.json'

            if (Test-Path -LiteralPath $runtimeSentinelPath) {
                try {
                    $sentinel = Get-Content -LiteralPath $runtimeSentinelPath -Raw | ConvertFrom-Json
                    $compilerVersion = if ($sentinel.PSObject.Properties.Match('compilerVersion').Count -gt 0) { [string]$sentinel.compilerVersion } else { $null }

                    # Check if this is a local tool installation
                    if ($sentinel.installationType -eq 'local-tool') {
                        $toolPath = [string]$sentinel.toolPath

                        if ($toolPath -and (Test-Path -LiteralPath $toolPath)) {
                            # Use direct executable path from local tool
                            $toolItem = Get-Item -LiteralPath $toolPath
                            return [pscustomobject]@{
                                AlcPath      = $toolItem.FullName
                                Version      = $compilerVersion
                                SentinelPath = $runtimeSentinelPath
                                IsLocalTool  = $false
                                Runtime      = $RuntimeVersion
                            }
                        } else {
                            throw "Local tool installation found but compiler executable not found at: $toolPath"
                        }
                    } else {
                        # Legacy path-based installation
                        $toolPath = [string]$sentinel.toolPath
                        if ($toolPath -and (Test-Path -LiteralPath $toolPath)) {
                            $toolItem = Get-Item -LiteralPath $toolPath
                            return [pscustomobject]@{
                                AlcPath      = $toolItem.FullName
                                Version      = $compilerVersion
                                SentinelPath = $runtimeSentinelPath
                                IsLocalTool  = $false
                            }
                        }
                    }
                } catch {
                    Write-Warning "Failed to parse runtime-specific sentinel: $($_.Exception.Message)"
                }
            }
        }
    }

    # Priority 2: Legacy approach (backward compatibility)
    $sentinelName = if ($ToolVersion) { "$ToolVersion.json" } else { 'default.json' }
    $sentinelPath = Join-Path -Path $alCacheDir -ChildPath $sentinelName

    if (-not (Test-Path -LiteralPath $sentinelPath)) {
        throw "Compiler provisioning sentinel not found. Runtime: $RuntimeVersion, Tool: $ToolVersion. Run `make download-compiler` before `make build`."
    }

    try {
        $sentinel = Get-Content -LiteralPath $sentinelPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse compiler sentinel at ${sentinelPath}: $($_.Exception.Message). Run `make download-compiler` before `make build`."
    }

    $toolPath = if ($sentinel) { [string]$sentinel.toolPath } else { $null }
    if (-not $toolPath) {
        throw "Compiler sentinel at $sentinelPath is missing toolPath. Run `make download-compiler` before `make build`."
    }

    $resolvedToolPath = Expand-FullPath -Path $toolPath
    if (-not (Test-Path -LiteralPath $resolvedToolPath)) {
        throw "AL compiler not found at ${resolvedToolPath} (sentinel ${sentinelPath}). Run `make download-compiler` before `make build`."
    }

    $toolItem = Get-Item -LiteralPath $resolvedToolPath
    $compilerVersion = if ($sentinel.PSObject.Properties.Match('compilerVersion').Count -gt 0) { [string]$sentinel.compilerVersion } else { $null }

    return [pscustomobject]@{
        AlcPath      = $toolItem.FullName
        Version      = $compilerVersion
        SentinelPath = $sentinelPath
        IsLocalTool  = $false
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
    if (-not $userHome) {
        throw 'Unable to determine home directory for symbol cache. Set ALBT_SYMBOL_CACHE_ROOT or run `make download-symbols` after fixing the environment.'
    }
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
        throw "Symbol cache directory not found at $cacheDir. Run `make download-symbols` before `make build`."
    }

    $manifestPath = Join-Path -Path $cacheDir -ChildPath 'symbols.lock.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Symbol manifest missing at $manifestPath. Run `make download-symbols` before `make build`."
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse symbol manifest at ${manifestPath}: $($_.Exception.Message). Run `make download-symbols` before `make build`."
    }

    return [pscustomobject]@{
        CacheDir     = (Get-Item -LiteralPath $cacheDir).FullName
        ManifestPath = $manifestPath
        Manifest     = $manifest
    }
}

function Test-AnalyzerDependencies {
    <#
    .SYNOPSIS
        Test if an analyzer has all required dependencies available
    .PARAMETER AnalyzerPath
        Path to the analyzer DLL to test
    #>
    param([string]$AnalyzerPath)

    if (-not (Test-Path -LiteralPath $AnalyzerPath)) {
        return $false
    }

    try {
        # Try to load the analyzer assembly to check for missing dependencies
        $bytes = [System.IO.File]::ReadAllBytes($AnalyzerPath)
        $assembly = [System.Reflection.Assembly]::Load($bytes)

        # Check if we can get the types (this will fail if dependencies are missing)
        $types = $assembly.GetTypes()
        return $true
    } catch {
        Write-Verbose "[albt] Analyzer dependency check failed for $(Split-Path -Leaf $AnalyzerPath): $($_.Exception.Message)"
        return $false
    }
}

function Get-EnabledAnalyzerPath {
    param(
        [string]$AppDir,
        [string]$CompilerDir
    )

    $settingsPath = Get-SettingsJsonPath $AppDir
    $dllMap = @{
        'CodeCop'               = 'Microsoft.Dynamics.Nav.CodeCop.dll'
        'UICop'                 = 'Microsoft.Dynamics.Nav.UICop.dll'
        'AppSourceCop'          = 'Microsoft.Dynamics.Nav.AppSourceCop.dll'
        'PerTenantExtensionCop' = 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll'
    }
    $supported = $dllMap.Keys
    $enabled = @()

    if ($settingsPath -and (Test-Path -LiteralPath $settingsPath)) {
        try {
            $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($json -and ($json.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $json.'al.codeAnalyzers') {
                $enabled = @($json.'al.codeAnalyzers')
            } elseif ($json) {
                if ($json.PSObject.Properties.Match('enableCodeCop').Count -gt 0 -and $json.enableCodeCop) { $enabled += 'CodeCop' }
                if ($json.PSObject.Properties.Match('enableUICop').Count -gt 0 -and $json.enableUICop) { $enabled += 'UICop' }
                if ($json.PSObject.Properties.Match('enableAppSourceCop').Count -gt 0 -and $json.enableAppSourceCop) { $enabled += 'AppSourceCop' }
                if ($json.PSObject.Properties.Match('enablePerTenantExtensionCop').Count -gt 0 -and $json.enablePerTenantExtensionCop) { $enabled += 'PerTenantExtensionCop' }
            }
        } catch {
            Write-Verbose "[albt] settings.json parse failed: $($_.Exception.Message)"
        }
    }

    $dllPaths = New-Object System.Collections.Generic.List[string]
    if (-not $enabled -or $enabled.Count -eq 0) { return $dllPaths }

    $workspaceRoot = (Get-Location).Path
    $appFull = try { (Resolve-Path $AppDir -ErrorAction Stop).Path } catch { Join-Path $workspaceRoot $AppDir }

    # Find analyzers directory - check both compiler directory and runtime-specific cache
    $analyzersDir = $null
    $runtimeAnalyzersDir = $null

    if ($CompilerDir -and (Test-Path -LiteralPath $CompilerDir)) {
        $candidate = Join-Path -Path $CompilerDir -ChildPath 'Analyzers'
        if (Test-Path -LiteralPath $candidate) {
            $analyzersDir = (Get-Item -LiteralPath $candidate).FullName
        } else {
            $analyzersDir = (Get-Item -LiteralPath $CompilerDir).FullName
        }
    }

    # Also check runtime-specific cache for LinterCop
    $toolCacheRoot = if ($env:ALBT_TOOL_CACHE) { $env:ALBT_TOOL_CACHE } else { Join-Path $env:USERPROFILE '.bc-tool-cache' }
    $runtimeCacheDirs = Get-ChildItem -Path (Join-Path $toolCacheRoot 'al') -Directory -Filter 'runtime-*' -ErrorAction SilentlyContinue
    foreach ($runtimeDir in $runtimeCacheDirs) {
        $runtimeAnalyzersCandidate = Join-Path $runtimeDir.FullName 'Analyzers'
        if (Test-Path -LiteralPath $runtimeAnalyzersCandidate) {
            $runtimeAnalyzersDir = (Get-Item -LiteralPath $runtimeAnalyzersCandidate).FullName
            break
        }
    }

    function Resolve-AnalyzerEntry {
        param([string]$Entry)

        $val = $Entry
        if ($null -eq $val) { return @() }

        if ($val -match '^\$\{analyzerFolder\}(.*)$' -and $analyzersDir) {
            $tail = $matches[1]
            if ($tail -and $tail[0] -notin @('\\','/')) { $val = Join-Path $analyzersDir $tail } else { $val = "$analyzersDir$tail" }
        }
        if ($val -match '^\$\{alExtensionPath\}(.*)$' -and $CompilerDir) {
            $tail2 = $matches[1]
            if ($tail2 -and $tail2[0] -notin @('\\','/')) { $val = Join-Path $CompilerDir $tail2 } else { $val = "$CompilerDir$tail2" }
        }
        if ($val -match '^\$\{compilerRoot\}(.*)$' -and $CompilerDir) {
            $tail3 = $matches[1]
            if ($tail3 -and $tail3[0] -notin @('\\','/')) { $val = Join-Path $CompilerDir $tail3 } else { $val = "$CompilerDir$tail3" }
        }

        if ($CompilerDir) {
            $val = $val.Replace('${alExtensionPath}', $CompilerDir)
            $val = $val.Replace('${compilerRoot}', $CompilerDir)
        }
        if ($analyzersDir) {
            $val = $val.Replace('${analyzerFolder}', $analyzersDir)
        }

        $val = $val.Replace('${workspaceFolder}', $workspaceRoot).Replace('${workspaceRoot}', $workspaceRoot).Replace('${appDir}', $appFull)
        $val = [regex]::Replace($val, '\$\{([^}]+)\}', '$1')

        $expanded = [Environment]::ExpandEnvironmentVariables($val)
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

        if (-not [IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $workspaceRoot $expanded
        }

        if (Test-Path $expanded -PathType Container) {
            return Get-ChildItem -Path $expanded -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }

        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($expanded)) {
            return Get-ChildItem -Path $expanded -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }

        if (Test-Path $expanded -PathType Leaf) { return @($expanded) }

        return @()
    }

    foreach ($item in $enabled) {
        $name = ($item | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -match '^\$\{([A-Za-z]+)\}$') { $name = $matches[1] }

        if ($supported -contains $name) {
            if ($analyzersDir -or $CompilerDir -or $runtimeAnalyzersDir) {
                $dll = $dllMap[$name]
                $searchRoots = @()
                if ($analyzersDir) { $searchRoots += $analyzersDir }
                if ($runtimeAnalyzersDir) { $searchRoots += $runtimeAnalyzersDir }
                if ($CompilerDir -and ($searchRoots -notcontains $CompilerDir)) { $searchRoots += $CompilerDir }

                $found = $null
                foreach ($root in $searchRoots) {
                    if (-not (Test-Path -LiteralPath $root)) { continue }
                    $candidate = Get-ChildItem -Path $root -Recurse -Filter $dll -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($candidate) { $found = $candidate; break }
                }

                if ($found -and -not $dllPaths.Contains($found.FullName)) {
                    $dllPaths.Add($found.FullName) | Out-Null
                } elseif (-not $found) {
                    Write-Verbose "[albt] Analyzer '$name' requested but $dll not found near compiler directory."
                }
            } else {
                Write-Verbose "[albt] Analyzer '$name' requested but compiler directory unavailable for resolution."
            }
        } else {
            (Resolve-AnalyzerEntry -Entry $name) | ForEach-Object {
                if ($_ -and -not $dllPaths.Contains($_)) { $dllPaths.Add($_) | Out-Null }
            }
        }
    }

    return $dllPaths
}


$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make build)"
    exit $Exit.Guard
}


Write-Section 'Project Analysis'

Write-Information "📋 PROJECT MANIFEST:" -InformationAction Continue
$appJson = Get-AppJsonObject $AppDir
if (-not $appJson) {
    Write-InfoLine "app.json" "Not found or invalid" '❌'
    Write-StatusLine "Ensure the project manifest exists before building" '❌'
    Write-Error "app.json not found or invalid under '$AppDir'. Ensure the project manifest exists before building."
    exit $Exit.GeneralError
}

$appName = if ($appJson -and $appJson.name) { $appJson.name } else { 'Unknown App' }
$appVersion = if ($appJson -and $appJson.version) { $appJson.version } else { '1.0.0.0' }
$appPublisher = if ($appJson -and $appJson.publisher) { $appJson.publisher } else { 'Unknown' }

Write-InfoLine "Status" "Found" '✅'
Write-InfoLine "App Name" $appName '📱'
Write-InfoLine "Version" $appVersion '🏷️'
Write-InfoLine "Publisher" $appPublisher '👤'

Write-Section 'Compiler Discovery'

Write-Information "🔍 COMPILER RESOLUTION:" -InformationAction Continue
$requestedToolVersion = $env:AL_TOOL_VERSION
$alcOverride = $env:ALBT_ALC_SHIM
if (-not $alcOverride -and $env:ALBT_ALC_PATH) { $alcOverride = $env:ALBT_ALC_PATH }

$alcPath = $null
$compilerVersion = $null
$compilerRoot = $null

if ($alcOverride) {
    Write-InfoLine "Source" "Override path" '🔧'
    $resolvedOverride = Expand-FullPath -Path $alcOverride
    if (-not (Test-Path -LiteralPath $resolvedOverride)) {
        Write-InfoLine "Status" "Override not found" '❌'
        Write-StatusLine "AL compiler override not found at $alcOverride" '❌'
        Write-Error "AL compiler override not found at $alcOverride."
        exit $Exit.MissingTool
    }
    $alcPath = (Get-Item -LiteralPath $resolvedOverride).FullName
    $compilerRoot = Split-Path -Parent $alcPath
    $compilerVersion = '(override)'
    $isLocalTool = $false
    $localToolDirectory = $null
    Write-InfoLine "Status" "Override found" '✅'
} else {
    Write-InfoLine "Source" "Provisioned tool" '📦'
    try {
        # Get runtime version for runtime-specific compiler selection
        $runtimeVersion = if ($appJson -and $appJson.runtime) { [string]$appJson.runtime } else { $null }
        $compilerInfo = Get-CompilerProvisioningInfo -ToolVersion $requestedToolVersion -RuntimeVersion $runtimeVersion

        $alcPath = $compilerInfo.AlcPath
        $compilerVersion = if ($compilerInfo.Version) { $compilerInfo.Version } else { $null }
        $runtimeInfo = if ($compilerInfo.PSObject.Properties.Match('Runtime').Count -gt 0) { $compilerInfo.Runtime } else { $null }

        if ($runtimeInfo) {
            Write-InfoLine "Status" "Found (Runtime $runtimeInfo)" '✅'
        } else {
            Write-InfoLine "Status" "Found" '✅'
        }
    } catch {
        Write-InfoLine "Status" "Not found" '❌'
        Write-StatusLine $_.Exception.Message '❌'
        Write-Error $_.Exception.Message
        exit $Exit.MissingTool
    }
    $compilerRoot = Split-Path -Parent $alcPath
}

$displayVersion = if ($compilerVersion) { $compilerVersion } else { "(unknown)" }
Write-InfoLine "Version" $displayVersion '🏷️'
Write-InfoLine "Path" $alcPath '📁'

Write-Information "⚙️ EXECUTION SETUP:" -InformationAction Continue

# Normalize invocation path for cross-platform execution
$alcCommand = $alcPath
$alcLaunchPath = $alcPath
$alcPreArgs = @()

if (-not $IsWindows) {
    $alcDir = Split-Path -Parent $alcPath
    $dllCandidate = Join-Path -Path $alcDir -ChildPath 'alc.dll'

    if (Test-Path -LiteralPath $dllCandidate) {
        $alcLaunchPath = (Get-Item -LiteralPath $dllCandidate).FullName
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-InfoLine "Host" "dotnet (via alc.dll)" '⚡'
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.dll') {
        $alcLaunchPath = (Get-Item -LiteralPath $alcPath).FullName
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-InfoLine "Host" "dotnet (direct dll)" '⚡'
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.exe') {
        $alcLaunchPath = $alcPath
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-InfoLine "Host" "dotnet (exe wrapper)" '⚡'
    }
} else {
    Write-InfoLine "Host" "native executable" '⚡'
}

Write-InfoLine "Launch Path" $alcLaunchPath '🚀'

Write-Section 'Symbol Cache Resolution'

Write-Information "📦 SYMBOL CACHE:" -InformationAction Continue
try {
    $symbolCacheInfo = Get-SymbolCacheInfo -AppJson $appJson
    Write-InfoLine "Status" "Found" '✅'
    $packageCount = 0
    if ($symbolCacheInfo.Manifest -and $symbolCacheInfo.Manifest.packages) {
        $packageNode = $symbolCacheInfo.Manifest.packages
        if ($packageNode -is [System.Collections.IDictionary]) {
            $packageCount = $packageNode.Count
        } elseif ($packageNode.PSObject) {
            $packageCount = @($packageNode.PSObject.Properties).Count
        }
    }
    Write-InfoLine "Packages" "$packageCount available" '📊'
    Write-InfoLine "Path" $symbolCacheInfo.CacheDir '📁'
} catch {
    Write-InfoLine "Status" "Not found" '❌'
    Write-StatusLine $_.Exception.Message '❌'
    Write-Error $_.Exception.Message
    exit $Exit.MissingTool
}
$packageCachePath = $symbolCacheInfo.CacheDir

Write-Section 'Analyzer Configuration'

Write-Information "🧹 CODE ANALYZERS:" -InformationAction Continue
$analyzerPaths = Get-EnabledAnalyzerPath -AppDir $AppDir -CompilerDir $compilerRoot

# Filter out empty or non-existent analyzer paths (parity with Linux)
$filteredAnalyzers = New-Object System.Collections.Generic.List[string]
foreach ($p in $analyzerPaths) {
    if ($p -and (Test-Path $p -PathType Leaf)) { [void]$filteredAnalyzers.Add($p) }
}

if ($filteredAnalyzers.Count -gt 0) {
    Write-InfoLine "Status" "$($filteredAnalyzers.Count) analyzers found" '✅'
    Write-Information "  📋 Configured analyzers:" -InformationAction Continue
    $filteredAnalyzers | ForEach-Object {
        $fileName = Split-Path $_ -Leaf
        Write-ListItem $fileName
    }
} else {
    Write-InfoLine "Status" "No analyzers configured" '⚠️'
    Write-StatusLine "Consider enabling analyzers in .vscode/settings.json" 'ℹ️'
}

Write-Section 'Output Configuration'

Write-Information "📤 BUILD OUTPUT:" -InformationAction Continue
$outputFullPath = Get-OutputPath $AppDir
if (-not $outputFullPath) {
    Write-InfoLine "Output Path" "Could not determine" '❌'
    Write-StatusLine "Verify the manifest and rerun the provisioning targets" '❌'
    Write-Error "[ERROR] Output path could not be determined from app.json. Verify the manifest and rerun the provisioning targets."
    exit $Exit.GeneralError
}

$outputFile = Split-Path -Path $outputFullPath -Leaf
Write-InfoLine "Target File" $outputFile '📄'
Write-InfoLine "Full Path" $outputFullPath '📁'

Write-Section 'Pre-Build Cleanup'

Write-Information "🧹 CLEANUP OPERATIONS:" -InformationAction Continue
$cleanupActions = 0

if (Test-Path $outputFullPath -PathType Leaf) {
    try {
        Remove-Item $outputFullPath -Force
        Write-InfoLine "Removed" "Previous build artifact (file)" '🗑️'
        $cleanupActions++
    } catch {
        Write-InfoLine "Error" "Failed to remove existing file" '❌'
        Write-StatusLine "Failed to remove ${outputFullPath}: $($_.Exception.Message)" '❌'
        Write-Error "[ERROR] Failed to remove ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}

if (Test-Path $outputFullPath -PathType Container) {
    try {
        Remove-Item $outputFullPath -Recurse -Force
        Write-InfoLine "Removed" "Conflicting directory" '🗑️'
        $cleanupActions++
    } catch {
        Write-InfoLine "Error" "Failed to remove conflicting directory" '❌'
        Write-StatusLine "Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)" '❌'
        Write-Error "[ERROR] Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}

if ($cleanupActions -eq 0) {
    Write-InfoLine "Status" "No cleanup needed" '✅'
} else {
    Write-InfoLine "Status" "$cleanupActions items cleaned" '✅'
}

Write-Section 'Compilation' "$appName v$appVersion"



Write-Information "⚙️ COMPILER ARGUMENTS:" -InformationAction Continue

# Build analyzer arguments correctly
# Ensure all paths are absolute for the compiler
$absoluteAppDir = (Resolve-Path -Path $AppDir).Path
$cmdArgs = @("/project:$absoluteAppDir", "/out:$outputFullPath", "/packagecachepath:$packageCachePath", "/parallel+")

Write-InfoLine "Project Dir" $AppDir '📁'
Write-InfoLine "Output File" $outputFile '📄'
Write-InfoLine "Symbol Cache" $packageCachePath '📦'
Write-InfoLine "Parallel" "Enabled" '⚡'

# Optional: pass ruleset if specified and the file exists and is non-empty
$rulesetPath = $env:RULESET_PATH
if ($rulesetPath) {
    $rsItem = Get-Item -LiteralPath $rulesetPath -ErrorAction SilentlyContinue
    if ($rsItem -and $rsItem.Length -gt 0) {
        Write-InfoLine "Ruleset" $rsItem.Name '📋'
        $cmdArgs += "/ruleset:$($rsItem.FullName)"
    } else {
        Write-InfoLine "Ruleset" "Not found or empty" '⚠️'
        Write-StatusLine "Ruleset not found or empty, skipping: $rulesetPath" '⚠️'
    }
} else {
    Write-InfoLine "Ruleset" "None specified" 'ℹ️'
}

if ($filteredAnalyzers.Count -gt 0) {
    Write-InfoLine "Analyzers" "$($filteredAnalyzers.Count) configured" '🧹'
    foreach ($analyzer in $filteredAnalyzers) {
        $cmdArgs += "/analyzer:$analyzer"
    }
} else {
    Write-InfoLine "Analyzers" "None configured" 'ℹ️'
}

# Optional: treat warnings as errors when requested via environment variable
if ($env:WARN_AS_ERROR -and ($env:WARN_AS_ERROR -eq '1' -or $env:WARN_AS_ERROR -match '^(?i:true|yes|on)$')) {
    Write-InfoLine "Warnings" "Treated as errors" '🚨'
    $cmdArgs += '/warnaserror+'
} else {
    Write-InfoLine "Warnings" "Allowed" 'ℹ️'
}

Write-Information "🚀 EXECUTING COMPILATION:" -InformationAction Continue
$alcInvokeArgs = @()
if ($alcPreArgs.Count -gt 0) { $alcInvokeArgs += $alcPreArgs }
$alcInvokeArgs += $cmdArgs

$startTime = Get-Date
Write-InfoLine "Compiler" $alcCommand '⚡'
Write-InfoLine "Started" $startTime.ToString('HH:mm:ss') '⏰'

# Execute the compiler from its own directory to ensure analyzer dependencies are resolved correctly
$currentLocation = Get-Location
try {
    if ($compilerRoot -and (Test-Path -LiteralPath $compilerRoot)) {
        Set-Location -LiteralPath $compilerRoot
        Write-Verbose "[albt] Set working directory to compiler root: $compilerRoot"
    }
    & $alcCommand @alcInvokeArgs
    $exitCode = $LASTEXITCODE
} finally {
    Set-Location $currentLocation.Path
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Section 'Build Results'

Write-Information "📊 COMPILATION RESULTS:" -InformationAction Continue
Write-InfoLine "Duration" ("{0:mm\:ss\.fff}" -f $duration) '⏱️'
Write-InfoLine "Exit Code" $exitCode $(if ($exitCode -eq 0) { '✅' } else { '❌' })

if ($exitCode -ne 0) {
    Write-InfoLine "Status" "Failed" '❌'

    Write-Section 'Summary'
    Write-Information "❌ Build compilation failed" -InformationAction Continue
    Write-StatusLine "Review the error messages above and fix the reported issues" '❌'
    exit $Exit.Analysis
} else {
    Write-InfoLine "Status" "Success" '✅'

    # Check if output file was actually created
    if (Test-Path $outputFullPath -PathType Leaf) {
        $outputInfo = Get-Item -LiteralPath $outputFullPath
        $fileSize = if ($outputInfo.Length -lt 1024) {
            "{0} bytes" -f $outputInfo.Length
        } elseif ($outputInfo.Length -lt 1048576) {
            "{0:N1} KB" -f ($outputInfo.Length / 1024)
        } else {
            "{0:N1} MB" -f ($outputInfo.Length / 1048576)
        }
        Write-InfoLine "Output Size" $fileSize '📏'
        Write-InfoLine "Output File" $outputFile '📄'
    }

    Write-Section 'Summary'
    Write-Information "🎉 Build completed successfully!" -InformationAction Continue
    Write-StatusLine "Application package is ready for deployment" '✅'
}

exit $Exit.Success
# ...implementation to be added...
