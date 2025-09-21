#requires -Version 7.2

# Windows Show-Analyzers Script
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
function Get-SettingsJsonPath { param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath '.vscode/settings.json'
    if (Test-Path $p1) { return $p1 }
    $p2 = '.vscode/settings.json'
    if (Test-Path $p2) { return $p2 }
    return $null
}
function Get-SettingsJsonObject { param([string]$AppDir)
    $path = Get-SettingsJsonPath $AppDir
    if (-not $path) { return $null }
    try { Get-Content $path -Raw | ConvertFrom-Json } catch { $null }
}
function Get-EnabledAnalyzers { param([string]$AppDir)
    $settings = Get-SettingsJsonObject $AppDir
    if ($settings -and ($settings.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settings.'al.codeAnalyzers') {
        return $settings.'al.codeAnalyzers'
    }
    return @()
}

# --- Compiler provisioning helpers ---
function Expand-FullPath {
    param([string]$Path)

    if (-not $Path) { return $null }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)

    if ($expanded.StartsWith('~')) {
        $home = $env:HOME
        if (-not $home -and $env:USERPROFILE) { $home = $env:USERPROFILE }
        if ($home) {
            $suffix = $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if ([string]::IsNullOrWhiteSpace($suffix)) {
                $expanded = $home
            } else {
                $expanded = Join-Path -Path $home -ChildPath $suffix
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
        throw "Compiler provisioning sentinel not found at $sentinelPath. Run `make download-compiler` before inspecting analyzers."
    }

    try {
        $sentinel = Get-Content -LiteralPath $sentinelPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse compiler sentinel at ${sentinelPath}: $($_.Exception.Message). Run `make download-compiler` before inspecting analyzers."
    }

    $toolPath = if ($sentinel) { [string]$sentinel.toolPath } else { $null }
    if (-not $toolPath) {
        throw "Compiler sentinel at $sentinelPath missing toolPath. Run `make download-compiler` before inspecting analyzers."
    }

    $resolvedToolPath = Expand-FullPath -Path $toolPath
    if (-not (Test-Path -LiteralPath $resolvedToolPath)) {
        throw "AL compiler not found at ${resolvedToolPath} (sentinel ${sentinelPath}). Run `make download-compiler` before inspecting analyzers."
    }

    $toolItem = Get-Item -LiteralPath $resolvedToolPath
    $compilerVersion = if ($sentinel.PSObject.Properties.Match('compilerVersion').Count -gt 0) { [string]$sentinel.compilerVersion } else { $null }

    return [pscustomobject]@{
        AlcPath      = $toolItem.FullName
        Version      = $compilerVersion
        SentinelPath = $sentinelPath
    }
}

function Get-EnabledAnalyzerPaths {
    param(
        [string]$AppDir,
        [string[]]$EnabledAnalyzers,
        [string]$CompilerDir
    )

    $dllMap = @{
        'CodeCop'               = 'Microsoft.Dynamics.Nav.CodeCop.dll'
        'UICop'                 = 'Microsoft.Dynamics.Nav.UICop.dll'
        'AppSourceCop'          = 'Microsoft.Dynamics.Nav.AppSourceCop.dll'
        'PerTenantExtensionCop' = 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll'
    }
    $supported = $dllMap.Keys

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
            $home = $env:HOME
            if (-not $home -and $env:USERPROFILE) { $home = $env:USERPROFILE }
            if ($home) {
                $suffix = $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                if ([string]::IsNullOrWhiteSpace($suffix)) {
                    $expanded = $home
                } else {
                    $expanded = Join-Path -Path $home -ChildPath $suffix
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

    $dllPaths = New-Object System.Collections.Generic.List[string]

    foreach ($item in $EnabledAnalyzers) {
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
    Write-Output "Run via make (e.g., make show-analyzers)"
    exit $Exit.Guard
}

$requestedToolVersion = $env:AL_TOOL_VERSION
$alcOverride = $env:ALBT_ALC_SHIM
if (-not $alcOverride -and $env:ALBT_ALC_PATH) { $alcOverride = $env:ALBT_ALC_PATH }

$alcPath = $null
$compilerRoot = $null
$compilerVersion = $null
$compilerWarning = $null

if ($alcOverride) {
    $resolvedOverride = Expand-FullPath -Path $alcOverride
    if (-not (Test-Path -LiteralPath $resolvedOverride)) {
        $compilerWarning = "AL compiler override not found at $alcOverride."
    } else {
        $alcPath = (Get-Item -LiteralPath $resolvedOverride).FullName
        $compilerRoot = Split-Path -Parent $alcPath
        $compilerVersion = '(override)'
    }
} else {
    try {
        $compilerInfo = Get-CompilerProvisioningInfo -ToolVersion $requestedToolVersion
        if ($compilerInfo) {
            $alcPath = $compilerInfo.AlcPath
            $compilerVersion = $compilerInfo.Version
            $compilerRoot = Split-Path -Parent $alcPath
        }
    } catch {
        $compilerWarning = $_.Exception.Message
    }
}

$enabledAnalyzers = Get-EnabledAnalyzers $AppDir
$enabledAnalyzers = @($enabledAnalyzers)
Write-Output "Enabled analyzers:"
if ($enabledAnalyzers -and $enabledAnalyzers.Count -gt 0) {
    $enabledAnalyzers | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Output "  (none)"
}

$analyzerPaths = Get-EnabledAnalyzerPaths -AppDir $AppDir -EnabledAnalyzers $enabledAnalyzers -CompilerDir $compilerRoot
$analyzerPaths = @($analyzerPaths)
if ($alcPath) {
    Write-Output "Compiler path: $alcPath"
    if ($compilerVersion) { Write-Output "Compiler version: $compilerVersion" }
} elseif ($compilerWarning) {
    Write-Warning $compilerWarning
} else {
    Write-Warning "AL compiler context unavailable. Run `make download-compiler` or set ALBT_ALC_PATH before re-running."
}

if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-Output "Analyzer DLL paths:"
    $analyzerPaths | ForEach-Object { Write-Output "  $_" }
} else {
    if ($enabledAnalyzers.Count -gt 0) {
        Write-Warning "Analyzer DLLs not found. Run `make download-compiler` so the compiler's Analyzers folder is available or update settings.json entries."
    } else {
        Write-Warning "No analyzer DLLs found."
    }
}
exit $Exit.Success
