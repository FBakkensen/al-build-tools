#requires -Version 7.2

# Windows Build Script
# Inlined helpers (formerly from lib/) to make this entrypoint self-contained.
param([string]$AppDir = "app")

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

function Get-CompilerProvisioningInfo {
    param([string]$ToolVersion)

    $toolCacheRoot = Get-ToolCacheRoot
    $alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
    $sentinelName = if ($ToolVersion) { "$ToolVersion.json" } else { 'default.json' }
    $sentinelPath = Join-Path -Path $alCacheDir -ChildPath $sentinelName

    if (-not (Test-Path -LiteralPath $sentinelPath)) {
        throw "Compiler provisioning sentinel not found at $sentinelPath. Run `make download-compiler` before `make build`."
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
    }
}

function Sanitize-PathSegment {
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

    $publisherDir = Join-Path -Path $cacheRoot -ChildPath (Sanitize-PathSegment -Value $AppJson.publisher)
    $appDirPath = Join-Path -Path $publisherDir -ChildPath (Sanitize-PathSegment -Value $AppJson.name)
    $cacheDir = Join-Path -Path $appDirPath -ChildPath (Sanitize-PathSegment -Value $AppJson.id)

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

function Get-EnabledAnalyzerPaths {
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

    $analyzersDir = $null
    if ($CompilerDir -and (Test-Path -LiteralPath $CompilerDir)) {
        $candidate = Join-Path -Path $CompilerDir -ChildPath 'Analyzers'
        if (Test-Path -LiteralPath $candidate) {
            $analyzersDir = (Get-Item -LiteralPath $candidate).FullName
        } else {
            $analyzersDir = (Get-Item -LiteralPath $CompilerDir).FullName
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
            if ($analyzersDir -or $CompilerDir) {
                $dll = $dllMap[$name]
                $searchRoots = @()
                if ($analyzersDir) { $searchRoots += $analyzersDir }
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


$Exit = Get-ExitCodes

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make build)"
    exit $Exit.Guard
}


# Load manifest for downstream decisions
$appJson = Get-AppJsonObject $AppDir
if (-not $appJson) {
    Write-Error "app.json not found or invalid under '$AppDir'. Ensure the project manifest exists before building."
    exit $Exit.GeneralError
}

# Discover AL compiler (allow override for tests)
$requestedToolVersion = $env:AL_TOOL_VERSION
$alcOverride = $env:ALBT_ALC_SHIM
if (-not $alcOverride -and $env:ALBT_ALC_PATH) { $alcOverride = $env:ALBT_ALC_PATH }

$alcPath = $null
$compilerVersion = $null
$compilerRoot = $null

if ($alcOverride) {
    $resolvedOverride = Expand-FullPath -Path $alcOverride
    if (-not (Test-Path -LiteralPath $resolvedOverride)) {
        Write-Error "AL compiler override not found at $alcOverride."
        exit $Exit.MissingTool
    }
    $alcPath = (Get-Item -LiteralPath $resolvedOverride).FullName
    $compilerRoot = Split-Path -Parent $alcPath
    $compilerVersion = '(override)'
} else {
    try {
        $compilerInfo = Get-CompilerProvisioningInfo -ToolVersion $requestedToolVersion
        $alcPath = $compilerInfo.AlcPath
        $compilerVersion = if ($compilerInfo.Version) { $compilerInfo.Version } else { $null }
    } catch {
        Write-Error $_.Exception.Message
        exit $Exit.MissingTool
    }
    $compilerRoot = Split-Path -Parent $alcPath
}

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
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.dll') {
        $alcLaunchPath = (Get-Item -LiteralPath $alcPath).FullName
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.exe') {
        $alcLaunchPath = $alcPath
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
    }
}

# Resolve symbol cache provisioned by download-symbols
try {
    $symbolCacheInfo = Get-SymbolCacheInfo -AppJson $appJson
} catch {
    Write-Error $_.Exception.Message
    exit $Exit.MissingTool
}
$packageCachePath = $symbolCacheInfo.CacheDir

# Resolve analyzer DLLs using compiler install as anchor
$analyzerPaths = Get-EnabledAnalyzerPaths -AppDir $AppDir -CompilerDir $compilerRoot

# Determine output path
$outputFullPath = Get-OutputPath $AppDir
if (-not $outputFullPath) {
    Write-Error "[ERROR] Output path could not be determined from app.json. Verify the manifest and rerun the provisioning targets."
    exit $Exit.GeneralError
}

# Summarize provisioning context for operator awareness
Write-Output "Using AL compiler: $alcLaunchPath"
if ($alcCommand -eq 'dotnet') {
    Write-Output "Compiler host: dotnet"
}
if ($compilerVersion -and $compilerVersion -ne '(override)') {
    Write-Output "Compiler version: $compilerVersion"
}
Write-Output "Symbol cache: $packageCachePath"
Write-Output ""

# Derive friendly app info for messages
$appName = if ($appJson -and $appJson.name) { $appJson.name } else { 'Unknown App' }
$appVersion = if ($appJson -and $appJson.version) { $appJson.version } else { '1.0.0.0' }
$outputFile = Split-Path -Path $outputFullPath -Leaf


if (Test-Path $outputFullPath -PathType Leaf) {
    try {
        Remove-Item $outputFullPath -Force
    } catch {
        Write-Error "[ERROR] Failed to remove ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
} else {
}
# Also check and remove any directory with the same name as the output file
if (Test-Path $outputFullPath -PathType Container) {
    try {
        Remove-Item $outputFullPath -Recurse -Force
    } catch {
        Write-Error "[ERROR] Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}
# List contents of output directory after removal

Write-Output "Building $appName v$appVersion..."

# Filter out empty or non-existent analyzer paths (parity with Linux)
$filteredAnalyzers = New-Object System.Collections.Generic.List[string]
foreach ($p in $analyzerPaths) {
    if ($p -and (Test-Path $p -PathType Leaf)) { [void]$filteredAnalyzers.Add($p) }
}

if ($filteredAnalyzers.Count -gt 0) {
    Write-Output "Using analyzers from settings.json:"
    $filteredAnalyzers | ForEach-Object { Write-Output "  - $_" }
    Write-Output ""
} else {
    Write-Output "No analyzers found or enabled in settings.json"
    Write-Output ""
}



# Build analyzer arguments correctly
$cmdArgs = @("/project:$AppDir", "/out:$outputFullPath", "/packagecachepath:$packageCachePath", "/parallel+")

# Optional: pass ruleset if specified and the file exists and is non-empty
$rulesetPath = $env:RULESET_PATH
if ($rulesetPath) {
    $rsItem = Get-Item -LiteralPath $rulesetPath -ErrorAction SilentlyContinue
    if ($rsItem -and $rsItem.Length -gt 0) {
        Write-Output "Using ruleset: $($rsItem.FullName)"
        $cmdArgs += "/ruleset:$($rsItem.FullName)"
    } else {
        Write-Warning "Ruleset not found or empty, skipping: $rulesetPath"
    }
}
if ($filteredAnalyzers.Count -gt 0) {
    foreach ($analyzer in $filteredAnalyzers) {
        $cmdArgs += "/analyzer:$analyzer"
    }
}

# Optional: treat warnings as errors when requested via environment variable
if ($env:WARN_AS_ERROR -and ($env:WARN_AS_ERROR -eq '1' -or $env:WARN_AS_ERROR -match '^(?i:true|yes|on)$')) {
    $cmdArgs += '/warnaserror+'
}

$alcInvokeArgs = @()
if ($alcPreArgs.Count -gt 0) { $alcInvokeArgs += $alcPreArgs }
$alcInvokeArgs += $cmdArgs

& $alcCommand @alcInvokeArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Output ""
    # Print a clean failure message without emitting a PowerShell error record
    Write-Host "Build failed with errors above." -ForegroundColor Red
    exit $Exit.Analysis
} else {
    Write-Output ""
    Write-Output "Build completed successfully: $outputFile"
}

exit $Exit.Success
# ...implementation to be added...
