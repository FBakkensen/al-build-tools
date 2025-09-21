#requires -Version 7.2

<#
.SYNOPSIS
    Display comprehensive AL analyzer configuration and status with structured formatting.

.DESCRIPTION
    Shows enabled analyzers, compiler information, and resolved analyzer DLL paths in a
    structured format suitable for both interactive display and automation.

.PARAMETER AppDir
    Directory containing .vscode/settings.json (defaults to current directory)

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
    $header = "🔧 ANALYZERS | {0}" -f $Title
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

function Write-ListItem {
    param([string]$Item, [string]$Icon = '→')
    Write-Information ("    {0} {1}" -f $Icon, $Item) -InformationAction Continue
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
function Get-EnabledAnalyzer { param([string]$AppDir)
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

function Get-EnabledAnalyzerPath {
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

$Exit = Get-ExitCode

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

$enabledAnalyzers = Get-EnabledAnalyzer $AppDir
$enabledAnalyzers = @($enabledAnalyzers)

Write-Section 'Enabled Analyzers Configuration'

Write-Information "📊 ANALYZER SETTINGS:" -InformationAction Continue
if ($enabledAnalyzers -and $enabledAnalyzers.Count -gt 0) {
    Write-InfoLine "Count" "$($enabledAnalyzers.Count) configured" '✅'
    Write-Information "  📋 Configured analyzers:" -InformationAction Continue
    $enabledAnalyzers | ForEach-Object { Write-ListItem $_ }
} else {
    Write-InfoLine "Count" "0 configured" '⚠️'
    Write-StatusLine "No analyzers are currently enabled in .vscode/settings.json" '⚠️'
}

Write-Section 'Compiler Status'

if ($alcPath) {
    Write-Information "🔨 COMPILER INFO:" -InformationAction Continue
    Write-InfoLine "Status" "Ready" '✅'
    if ($compilerVersion) {
        Write-InfoLine "Version" $compilerVersion '📦'
    }
    Write-InfoLine "Path" $alcPath '📁'
} elseif ($compilerWarning) {
    Write-Information "🔨 COMPILER INFO:" -InformationAction Continue
    Write-StatusLine $compilerWarning '❌'
} else {
    Write-Information "🔨 COMPILER INFO:" -InformationAction Continue
    Write-StatusLine "AL compiler context unavailable. Run 'make download-compiler' or set ALBT_ALC_PATH" '❌'
}

$analyzerPaths = Get-EnabledAnalyzerPath -AppDir $AppDir -EnabledAnalyzers $enabledAnalyzers -CompilerDir $compilerRoot
$analyzerPaths = @($analyzerPaths)

Write-Section 'Analyzer DLL Resolution'

if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-Information "🔍 RESOLVED ANALYZER DLLS:" -InformationAction Continue
    Write-InfoLine "Found" "$($analyzerPaths.Count) DLL files" '✅'
    Write-Information "  📂 Resolved DLL paths:" -InformationAction Continue
    $analyzerPaths | ForEach-Object {
        $fileName = Split-Path $_ -Leaf
        $dirPath = Split-Path $_ -Parent
        Write-Information ("    → {0}" -f $fileName) -InformationAction Continue
        Write-Information ("      {0}" -f $dirPath) -InformationAction Continue
    }
} else {
    Write-Information "🔍 RESOLVED ANALYZER DLLS:" -InformationAction Continue
    Write-InfoLine "Found" "0 DLL files" '❌'
    if ($enabledAnalyzers.Count -gt 0) {
        Write-StatusLine "Analyzer DLLs not found. Run 'make download-compiler' so the compiler's Analyzers folder is available or update settings.json entries" '❌'
    } else {
        Write-StatusLine "No analyzer DLLs found because no analyzers are configured" '⚠️'
    }
}

Write-Section 'Summary'

$totalEnabled = $enabledAnalyzers.Count
$totalResolved = $analyzerPaths.Count
$missingCount = [Math]::Max(0, $totalEnabled - $totalResolved)

Write-Information "📋 ANALYZER SUMMARY:" -InformationAction Continue
Write-InfoLine "Configured" "$totalEnabled analyzers" '📊'
Write-InfoLine "Resolved" "$totalResolved DLL files" '🔍'
if ($missingCount -gt 0) {
    Write-InfoLine "Missing" "$missingCount DLL files" '⚠️'
}

if ($totalResolved -eq $totalEnabled -and $totalEnabled -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information "✅ All configured analyzers resolved successfully!" -InformationAction Continue
} elseif ($totalEnabled -eq 0) {
    Write-Information "" -InformationAction Continue
    Write-Information "⚠️ No analyzers configured. Consider enabling CodeCop, UICop, or other analyzers in .vscode/settings.json" -InformationAction Continue
} else {
    Write-Information "" -InformationAction Continue
    Write-Information "⚠️ Some analyzers could not be resolved. Check compiler installation and settings.json configuration" -InformationAction Continue
}

exit $Exit.Success
