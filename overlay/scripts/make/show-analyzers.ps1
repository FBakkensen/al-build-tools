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

# --- AL extension + analyzer resolution (from common.ps1) ---
function Get-HighestVersionALExtension {
    $roots = @(
        (Join-Path $env:USERPROFILE '.vscode\\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-insiders\\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-server\\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-server-insiders\\extensions')
    )
    $candidates = @()
    foreach ($root in $roots) { if (Test-Path $root) { $items = Get-ChildItem -Path $root -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue; if ($items) { $candidates += $items } } }
    if (-not $candidates -or $candidates.Count -eq 0) { return $null }
    $parseVersion = { param($name) if ($name -match 'ms-dynamics-smb\.al-([0-9]+(\.[0-9]+)*)') { [version]$matches[1] } else { [version]'0.0.0' } }
    $withVersion = $candidates | ForEach-Object { $ver = & $parseVersion $_.Name; $isInsiders = if ($_.FullName -match 'insiders') { 1 } else { 0 }; [PSCustomObject]@{ Ext=$_; Version=$ver; Insiders=$isInsiders } }
    ($withVersion | Sort-Object -Property Version, Insiders -Descending | Select-Object -First 1).Ext
}
function Get-EnabledAnalyzerPaths { param([string]$AppDir)
    $settingsPath = Get-SettingsJsonPath $AppDir
    $dllMap = @{ 'CodeCop'='Microsoft.Dynamics.Nav.CodeCop.dll'; 'UICop'='Microsoft.Dynamics.Nav.UICop.dll'; 'AppSourceCop'='Microsoft.Dynamics.Nav.AppSourceCop.dll'; 'PerTenantExtensionCop'='Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll' }
    $supported = @('CodeCop','UICop','AppSourceCop','PerTenantExtensionCop')
    $enabled = @()
    if ($settingsPath -and (Test-Path $settingsPath)) {
        try {
            $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($json -and ($json.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $json.'al.codeAnalyzers') {
                $enabled = @($json.'al.codeAnalyzers')
            } elseif ($json -and (
                ($json.PSObject.Properties.Match('enableCodeCop').Count -gt 0 -and $json.enableCodeCop) -or
                ($json.PSObject.Properties.Match('enableUICop').Count -gt 0 -and $json.enableUICop) -or
                ($json.PSObject.Properties.Match('enableAppSourceCop').Count -gt 0 -and $json.enableAppSourceCop) -or
                ($json.PSObject.Properties.Match('enablePerTenantExtensionCop').Count -gt 0 -and $json.enablePerTenantExtensionCop)
            )) {
                if ($json.PSObject.Properties.Match('enableCodeCop').Count -gt 0 -and $json.enableCodeCop) { $enabled += 'CodeCop' }
                if ($json.PSObject.Properties.Match('enableUICop').Count -gt 0 -and $json.enableUICop) { $enabled += 'UICop' }
                if ($json.PSObject.Properties.Match('enableAppSourceCop').Count -gt 0 -and $json.enableAppSourceCop) { $enabled += 'AppSourceCop' }
                if ($json.PSObject.Properties.Match('enablePerTenantExtensionCop').Count -gt 0 -and $json.enablePerTenantExtensionCop) { $enabled += 'PerTenantExtensionCop' }
            }
        } catch { }
    }
    $alExt = Get-HighestVersionALExtension
    $workspaceRoot = (Get-Location).Path
    $appFull = try { (Resolve-Path $AppDir -ErrorAction Stop).Path } catch { Join-Path $workspaceRoot $AppDir }
    $analyzersDir = if ($alExt) { Join-Path $alExt.FullName 'bin/Analyzers' } else { $null }
    function Resolve-AnalyzerEntry { param([string]$Entry)
        $val = $Entry; if ($null -eq $val) { return @() }
        if ($val -match '^\$\{analyzerFolder\}(.*)$' -and $analyzersDir) { $tail = $matches[1]; if ($tail -and $tail[0] -notin @('\\','/')) { $val = Join-Path $analyzersDir $tail } else { $val = "$analyzersDir$tail" } }
        if ($val -match '^\$\{alExtensionPath\}(.*)$' -and $alExt) { $tail2 = $matches[1]; if ($tail2 -and $tail2[0] -notin @('\\','/')) { $val = Join-Path $alExt.FullName $tail2 } else { $val = "$($alExt.FullName)$tail2" } }
        if ($alExt) { $val = $val.Replace('${alExtensionPath}', $alExt.FullName); $val = $val.Replace('${analyzerFolder}', $analyzersDir) }
        $val = $val.Replace('${workspaceFolder}', $workspaceRoot).Replace('${workspaceRoot}', $workspaceRoot).Replace('${appDir}', $appFull)
        $val = [regex]::Replace($val, '\$\{([^}]+)\}', '$1')
        $val = [Environment]::ExpandEnvironmentVariables($val); if ($val.StartsWith('~')) { $val = $val -replace '^~', $env:USERPROFILE }
        if (-not [IO.Path]::IsPathRooted($val)) { $val = Join-Path $workspaceRoot $val }
        if (Test-Path $val -PathType Container) { return Get-ChildItem -Path $val -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($val)) { return Get-ChildItem -Path $val -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
        if (Test-Path $val -PathType Leaf) { return @($val) }
        return @()
    }
    $dllPaths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $enabled) {
        $name = ($item | Out-String).Trim()
        if ($name -match '^\$\{([A-Za-z]+)\}$') { $name = $matches[1] }
        if ($supported -contains $name) {
            if ($alExt) { $dll = $dllMap[$name]; if ($dll) { $found = Get-ChildItem -Path $alExt.FullName -Recurse -Filter $dll -ErrorAction SilentlyContinue | Select-Object -First 1; if ($found) { $dllPaths.Add($found.FullName) } } }
        } else {
            (Resolve-AnalyzerEntry -Entry $name) | ForEach-Object { if ($_ -and -not $dllPaths.Contains($_)) { $dllPaths.Add($_) } }
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

$enabledAnalyzers = Get-EnabledAnalyzers $AppDir
$enabledAnalyzers = @($enabledAnalyzers)
Write-Output "Enabled analyzers:"
if ($enabledAnalyzers -and $enabledAnalyzers.Count -gt 0) {
    $enabledAnalyzers | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Output "  (none)"
}

$analyzerPaths = Get-EnabledAnalyzerPaths $AppDir
$analyzerPaths = @($analyzerPaths)
if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-Output "Analyzer DLL paths:"
    $analyzerPaths | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Warning "No analyzer DLLs found."
}
exit $Exit.Success
