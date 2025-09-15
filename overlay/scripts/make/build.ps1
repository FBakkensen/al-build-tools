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
function Get-PackageCachePath { param([string]$AppDir) (Join-Path -Path $AppDir -ChildPath '.alpackages') }

# --- AL compiler discovery (from common.ps1) ---
function Get-HighestVersionALExtension {
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    $roots = @()
    if ($userHome) {
        $roots = @(
            (Join-Path $userHome (Join-Path '.vscode' 'extensions')),
            (Join-Path $userHome (Join-Path '.vscode-insiders' 'extensions')),
            (Join-Path $userHome (Join-Path '.vscode-server' 'extensions')),
            (Join-Path $userHome (Join-Path '.vscode-server-insiders' 'extensions'))
        )
    }
    $candidates = @()
    foreach ($root in $roots) { if (Test-Path $root) { $items = Get-ChildItem -Path $root -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue; if ($items) { $candidates += $items } } }
    if (-not $candidates -or $candidates.Count -eq 0) { return $null }
    $parseVersion = { param($name)
        if ($name -match 'ms-dynamics-smb\.al-([0-9]+(\.[0-9]+)*)') { return [version]$matches[1] } else { return [version]'0.0.0' }
    }
    $withVersion = $candidates | ForEach-Object { $ver = & $parseVersion $_.Name; $isInsiders = if ($_.FullName -match 'insiders') { 1 } else { 0 }; [PSCustomObject]@{ Ext = $_; Version = $ver; Insiders = $isInsiders } }
    $highest = $withVersion | Sort-Object -Property Version, Insiders -Descending | Select-Object -First 1
    if ($highest) { return $highest.Ext } else { return $null }
}
function Get-ALCompilerPath {
    $alExt = Get-HighestVersionALExtension
    if ($alExt) { $alc = Get-ChildItem -Path $alExt.FullName -Recurse -Filter 'alc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($alc) { return $alc.FullName } }
    return $null
}

# --- Analyzer paths (from common.ps1 + json helpers) ---
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
        } catch {
            Write-Verbose "[albt] settings.json parse failed: $($_.Exception.Message)"
        }
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
    Write-Output "Run via make (e.g., make build)"
    exit $Exit.Guard
}


# Discover AL compiler (allow test shim override)
$alcShim = $env:ALBT_ALC_SHIM
if ($alcShim) {
    $alcPath = $alcShim
} else {
    $alcPath = Get-ALCompilerPath
}
if (-not $alcPath) {
    Write-Error "AL Compiler not found. Please ensure AL extension is installed in VS Code."
    exit $Exit.MissingTool
}

# Get enabled analyzer DLL paths
$analyzerPaths = Get-EnabledAnalyzerPaths $AppDir


# Get output and package cache paths
$outputFullPath = Get-OutputPath $AppDir
if (-not $outputFullPath) {
    Write-Error "[ERROR] Output path could not be determined. Check app.json and Get-OutputPath function."
    exit 1
}
$packageCachePath = Get-PackageCachePath $AppDir
if (-not $packageCachePath) {
    Write-Error "[ERROR] Package cache path could not be determined."
    exit 1
}

# Derive friendly app info for messages
$appJson = Get-AppJsonObject $AppDir
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

& $alcPath @cmdArgs
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
