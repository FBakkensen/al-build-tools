#requires -Version 7.2

<#
.SYNOPSIS
    Install or update the AL compiler dotnet tool with structured status reporting.

.DESCRIPTION
    Ensures the AL compiler dotnet tool is installed for the runtime declared in app.json.
    Parses app.json to determine the runtime, maintains a sentinel under ~/.bc-tool-cache/al,
    and installs/updates the Microsoft.Dynamics.BusinessCentral.Development.Tools dotnet tool
    when the runtime increases, the sentinel is missing, or the compiler binaries are absent.
    Also downloads the BusinessCentral.LinterCop analyzer.

.PARAMETER AppDir
    Directory that contains app.json (defaults to "app" like build.ps1). You can also set
    ALBT_APP_DIR to override when the parameter is omitted.

.NOTES
    Optional environment variables:
      - AL_TOOL_VERSION: explicit version passed through make to select a tool version.
      - ALBT_TOOL_CACHE_ROOT: override for the default ~/.bc-tool-cache location.
      - ALBT_APP_DIR: override for default app directory when -AppDir omitted.
      - ALBT_FORCE_LINTERCOP: set to 1/true/yes/on to force re-download of BusinessCentral.LinterCop analyzer.

    This script uses Write-Information for output to ensure compatibility with different
    PowerShell hosts and automation scenarios.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]

#[CmdletBinding()]
param(
    [string]$AppDir = 'app'
)

if (-not $PSBoundParameters.ContainsKey('AppDir') -and $env:ALBT_APP_DIR) {
    $AppDir = $env:ALBT_APP_DIR
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# --- Formatting Helpers ---
function Write-Section {
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 COMPILER | {0}" -f $Title
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

function Write-Activity {
    param([string]$Activity, [string]$Status = '', [string]$Icon = '⏳')
    if ($Status) {
        Write-Information ("  {0} {1}: {2}" -f $Icon, $Activity, $Status) -InformationAction Continue
    } else {
        Write-Information ("  {0} {1}" -f $Icon, $Activity) -InformationAction Continue
    }
}

# --- Constants ---
$ToolExecutableNames = @('alc.exe', 'alc')

function Get-ToolPackageId {
    # Mirror https://github.com/StefanMaron/AL-Dependency-MCP-Server/src/cli/al-installer.ts logic:
    # Windows uses the generic package, Linux/macOS use platform-specific IDs.
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return 'microsoft.dynamics.businesscentral.development.tools'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return 'microsoft.dynamics.businesscentral.development.tools.linux'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return 'microsoft.dynamics.businesscentral.development.tools.osx'
    }
    return 'microsoft.dynamics.businesscentral.development.tools'
}

$ToolPackageId = Get-ToolPackageId
$AllToolPackageIds = @(
    'microsoft.dynamics.businesscentral.development.tools',
    'microsoft.dynamics.businesscentral.development.tools.linux',
    'microsoft.dynamics.businesscentral.development.tools.osx'
)
$candidatePackageIds = @()
foreach ($pkgId in @($ToolPackageId) + $AllToolPackageIds) {
    if ($pkgId -and -not ($candidatePackageIds -contains $pkgId)) {
        $candidatePackageIds += $pkgId
    }
}

# --- Helpers ---
function Resolve-AppJsonPath {
    param([string]$AppDirectory)

    if (-not $AppDirectory) { $AppDirectory = 'app' }
    $candidate = Join-Path -Path $AppDirectory -ChildPath 'app.json'
    if (Test-Path -LiteralPath $candidate) {
        return (Get-Item -LiteralPath $candidate).FullName
    }
    if (Test-Path -LiteralPath 'app.json') {
        return (Get-Item -LiteralPath 'app.json').FullName
    }
    throw "app.json not found. Provide -AppDir or run from project root."
}

function Read-JsonFile {
    param([string]$Path)
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON from ${Path}: $($_.Exception.Message)"
    }
}

function Expand-FullPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    try {
        return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).ProviderPath
    } catch {
        return [System.IO.Path]::GetFullPath($expanded)
    }
}

function Get-ToolCacheRoot {
    $override = $env:ALBT_TOOL_CACHE_ROOT
    if ($override) {
        return Expand-FullPath -Path $override
    }

    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) {
        throw 'Unable to determine home directory for tool cache.'
    }
    return Join-Path -Path $userHome -ChildPath '.bc-tool-cache'
}

function Initialize-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function ConvertTo-Version {
    param([Alias('Input')][string]$Value)
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        return [version]$Value
    } catch {
        return $null
    }
}

function Get-DotnetRoot {
    if ($env:DOTNET_CLI_HOME) {
        $candidate = Join-Path -Path $env:DOTNET_CLI_HOME -ChildPath (Join-Path '.dotnet' 'tools')
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).ProviderPath }
    }
    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to locate dotnet tools root.' }
    return Join-Path -Path $userHome -ChildPath (Join-Path '.dotnet' 'tools')
}

function Test-DotnetAvailable {
    try {
        $null = Get-Command -Name 'dotnet' -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-InstalledToolInfo {
    param([string]$ToolsRoot, [string[]]$PackageIds)

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @($ToolPackageId)
    }

    $orderedCandidates = @()
    foreach ($candidate in $PackageIds) {
        if ($candidate) { $orderedCandidates += $candidate.ToLowerInvariant() }
    }

    $dotnetListArgs = @('tool', 'list', '--global', '--format', 'json')
    # IMPORTANT: A previous implementation incorrectly set DOTNET_CLI_HOME to the *parent* of the tools root (the .dotnet folder).
    # The dotnet global tools layout is: <DOTNET_CLI_HOME>/.dotnet/tools. Therefore, for a tools root of <Home>/.dotnet/tools,
    # DOTNET_CLI_HOME must be <Home>, not <Home>/.dotnet. Setting it to <Home>/.dotnet caused dotnet to inspect <Home>/.dotnet/.dotnet/tools
    # which does not exist, yielding an empty tool list and preventing version detection after install.
    $originalDotnetCliHome = $env:DOTNET_CLI_HOME
    $restoreDotnetCliHome = $false
    try {
        if ($ToolsRoot) {
            try {
                $resolvedToolsRoot = (Resolve-Path -LiteralPath $ToolsRoot -ErrorAction Stop).ProviderPath
            } catch { $resolvedToolsRoot = $ToolsRoot }
            $leaf = Split-Path -Leaf $resolvedToolsRoot
            if ($leaf -ieq 'tools') {
                $parent = Split-Path -Parent $resolvedToolsRoot -ErrorAction SilentlyContinue
                $parentLeaf = if ($parent) { Split-Path -Leaf $parent } else { $null }
                if ($parentLeaf -ieq '.dotnet') {
                    # Home directory is one level above '.dotnet'
                    $candidateHome = Split-Path -Parent $parent -ErrorAction SilentlyContinue
                } else {
                    # Unexpected layout; fall back to parent of tools
                    $candidateHome = $parent
                }
                if ($candidateHome -and (Test-Path -LiteralPath $candidateHome)) {
                    $env:DOTNET_CLI_HOME = $candidateHome
                    $restoreDotnetCliHome = $true
                }
            }
        }
        $jsonText = & dotnet @dotnetListArgs
    } finally {
        if ($restoreDotnetCliHome) { $env:DOTNET_CLI_HOME = $originalDotnetCliHome }
    }
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    try {
        $parsed = $jsonText | ConvertFrom-Json
        if (-not $parsed -or -not $parsed.data) { return $null }
        foreach ($preferred in $orderedCandidates) {
            foreach ($entry in $parsed.data) {
                $entryId = if ($entry.packageId) { $entry.packageId.ToString().ToLowerInvariant() } else { $null }
                if ($entryId -eq $preferred) {
                    return [pscustomobject]@{
                        packageId = $entryId
                        version = [string]$entry.version
                    }
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-CompilerPath {
    param([string]$ToolsRoot, [string]$ToolVersion, [string[]]$PackageIds)

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @($ToolPackageId)
    }

    $storeRoot = Join-Path -Path $ToolsRoot -ChildPath '.store'
    if (-not (Test-Path -LiteralPath $storeRoot)) { return $null }

    foreach ($candidatePackageId in $PackageIds) {
        if (-not $candidatePackageId) { continue }
        $packageDirName = $candidatePackageId.ToLower()
        $packageRoot = Join-Path -Path $storeRoot -ChildPath $packageDirName
        if (-not (Test-Path -LiteralPath $packageRoot)) { continue }

        $searchDepth = 6

        $items = Get-ChildItem -Path $packageRoot -Recurse -File -Depth $searchDepth -ErrorAction SilentlyContinue |
            Where-Object { $ToolExecutableNames -contains $_.Name }

        if ($ToolVersion) {
            $items = $items | Where-Object { $_.FullName -match [regex]::Escape($ToolVersion) }
        }

        $candidate = $items | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Invoke-DotnetToolCommand {
    param([string[]]$Arguments)
    Write-Activity "Executing dotnet command" ("dotnet {0}" -f ($Arguments -join ' ')) '⚡'
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet tool command failed with exit code $LASTEXITCODE"
    }
}

function Write-Sentinel {
    param([string]$Path, [string]$CompilerVersion, [string]$Runtime, [string]$ToolPath, [string]$PackageId)

    $payload = [ordered]@{
        compilerVersion = $CompilerVersion
        runtime = $Runtime
        toolPath = $ToolPath
        packageId = $PackageId
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    $json = $payload | ConvertTo-Json -Depth 4
    $json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Install-LinterCopAnalyzer {
    param([string]$CompilerPath)
    if (-not $CompilerPath) { return }
    try {
        $linterCopUrl = 'https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/BusinessCentral.LinterCop.dll'
        $forceLinterCop = $false
        if ($env:ALBT_FORCE_LINTERCOP -and ($env:ALBT_FORCE_LINTERCOP -match '^(?i:1|true|yes|on)$')) { $forceLinterCop = $true }

        $compilerDir = Split-Path -Parent $CompilerPath -ErrorAction Stop
        $analyzersDir = Join-Path -Path $compilerDir -ChildPath 'Analyzers'
        if (-not (Test-Path -LiteralPath $analyzersDir)) {
            try { [void](New-Item -ItemType Directory -Path $analyzersDir -Force) } catch { throw "Unable to create analyzers directory at ${analyzersDir}: $($_.Exception.Message)" }
        }

        $targetDll = Join-Path -Path $analyzersDir -ChildPath 'BusinessCentral.LinterCop.dll'
        $needDownload = $true
        if ((Test-Path -LiteralPath $targetDll) -and -not $forceLinterCop) { $needDownload = $false }

        if (-not $needDownload) {
            Write-InfoLine "LinterCop Status" "Already present" '✅'
            Write-InfoLine "Location" $targetDll '📁'
            Write-StatusLine "Set ALBT_FORCE_LINTERCOP=1 to force re-download" 'ℹ️'
        } else {
            Write-Activity "Downloading LinterCop analyzer" $linterCopUrl '📥'
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -Uri $linterCopUrl -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
                $fileInfo = Get-Item -LiteralPath $tempFile -ErrorAction Stop
                if ($fileInfo.Length -le 0) { throw 'Downloaded file is empty.' }
                Move-Item -LiteralPath $tempFile -Destination $targetDll -Force
                Write-InfoLine "LinterCop Status" "Downloaded successfully" '✅'
                Write-InfoLine "Location" $targetDll '📁'
            } catch {
                Write-Warning "Failed to download LinterCop analyzer: $($_.Exception.Message)"
                try {
                    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
                } catch {
                    Write-Verbose "[albt] temp file cleanup failed: $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Warning "Unexpected error while ensuring LinterCop analyzer: $($_.Exception.Message)"
    }
}

# --- Execution ---
Write-Section 'Environment Analysis'

Write-Information "🔍 PREREQUISITE CHECK:" -InformationAction Continue
if (-not (Test-DotnetAvailable)) {
    Write-InfoLine "dotnet CLI" "Not found" '❌'
    Write-StatusLine "Install .NET SDK to provision the AL compiler" '❌'
    throw 'dotnet CLI not found on PATH. Install .NET SDK to provision the AL compiler.'
}
Write-InfoLine "dotnet CLI" "Available" '✅'

Write-Information "📋 PROJECT CONFIGURATION:" -InformationAction Continue
$appJsonPath = Resolve-AppJsonPath -AppDirectory $AppDir
$appJson = Read-JsonFile -Path $appJsonPath
if (-not $appJson.runtime) {
    Write-InfoLine "app.json" "Found" '⚠️'
    Write-StatusLine 'Runtime not specified in app.json ("runtime" property missing)' '❌'
    throw 'Runtime not specified in app.json ("runtime" property missing).'
}
$appRuntime = [string]$appJson.runtime
Write-InfoLine "app.json" "Found" '✅'
Write-InfoLine "Target Runtime" $appRuntime '🎯'

$requestedToolVersion = $env:AL_TOOL_VERSION
if ($requestedToolVersion) {
    Write-InfoLine "Requested Version" $requestedToolVersion '📌'
}

Write-Section 'Cache Analysis'

$toolCacheRoot = Get-ToolCacheRoot
Initialize-Directory -Path $toolCacheRoot
$alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
Initialize-Directory -Path $alCacheDir
$sentinelName = if ($requestedToolVersion) { "$requestedToolVersion.json" } else { 'default.json' }
$sentinelPath = Join-Path -Path $alCacheDir -ChildPath $sentinelName

Write-Information "📂 CACHE STRUCTURE:" -InformationAction Continue
Write-InfoLine "Cache Root" $toolCacheRoot '📁'
Write-InfoLine "AL Cache Dir" $alCacheDir '📁'
Write-InfoLine "Sentinel File" $sentinelName '📋'

$existingSentinel = $null
if (Test-Path -LiteralPath $sentinelPath) {
    try {
        $existingSentinel = Read-JsonFile -Path $sentinelPath
    } catch {
        Write-Warning "Unable to read sentinel ${sentinelPath}: $($_.Exception.Message)"
    }
}

$sentinelRuntime = if ($existingSentinel) { [string]$existingSentinel.runtime } else { $null }
$sentinelVersion = if ($existingSentinel) { [string]$existingSentinel.compilerVersion } else { $null }
$sentinelToolPath = if ($existingSentinel) { [string]$existingSentinel.toolPath } else { $null }
$sentinelPackageId = if ($existingSentinel -and ($existingSentinel.PSObject.Properties.Name -contains 'packageId')) { [string]$existingSentinel.packageId } else { $null }

$currentRuntimeVersion = ConvertTo-Version -Input $appRuntime
$previousRuntimeVersion = ConvertTo-Version -Input $sentinelRuntime
$runtimeIncreased = $false
if ($currentRuntimeVersion -and $previousRuntimeVersion) {
    if ($currentRuntimeVersion -gt $previousRuntimeVersion) { $runtimeIncreased = $true }
} elseif (-not $previousRuntimeVersion) {
    $runtimeIncreased = $true
}

$toolsRoot = Get-DotnetRoot
$installedToolInfo = Get-InstalledToolInfo -ToolsRoot $toolsRoot -PackageIds $candidatePackageIds
$installedToolVersion = if ($installedToolInfo) { [string]$installedToolInfo.version } else { $null }
$installedPackageId = if ($installedToolInfo) { [string]$installedToolInfo.packageId } else { $null }

 $expectedToolVersion = if ($requestedToolVersion) { $requestedToolVersion } else { $sentinelVersion }
 if (-not $expectedToolVersion) {
     $expectedToolVersion = $installedToolVersion
 }

$compilerPath = $null
if ($expectedToolVersion) {
    $compilerPath = Get-CompilerPath -ToolsRoot $toolsRoot -ToolVersion $expectedToolVersion -PackageIds $candidatePackageIds
}
if (-not $compilerPath -and $sentinelToolPath) {
    if (Test-Path -LiteralPath $sentinelToolPath) {
        $compilerPath = (Resolve-Path -LiteralPath $sentinelToolPath).ProviderPath
    }
}

if (-not $existingSentinel -and $compilerPath) {
    $runtimeIncreased = $false
}

 $installRequired = $false
 if (-not $compilerPath) { $installRequired = $true }
 if ($runtimeIncreased) { $installRequired = $true }
 if ($requestedToolVersion -and $sentinelVersion -and ($requestedToolVersion -ne $sentinelVersion)) { $installRequired = $true }
 if (-not $existingSentinel -and -not $compilerPath) { $installRequired = $true }

 # If tool is already installed and no specific reason to update, don't try to install
Write-Section 'Installation Decision'

Write-Information "🤔 DECISION ANALYSIS:" -InformationAction Continue
$compilerFoundText = if ($compilerPath) { "Yes" } else { "No" }
$compilerFoundIcon = if ($compilerPath) { '✅' } else { '❌' }
Write-InfoLine "Compiler Found" $compilerFoundText $compilerFoundIcon

$runtimeIncreasedText = if ($runtimeIncreased) { "Yes" } else { "No" }
$runtimeIncreasedIcon = if ($runtimeIncreased) { '⬆️' } else { '➡️' }
Write-InfoLine "Runtime Increased" $runtimeIncreasedText $runtimeIncreasedIcon

$versionRequestedText = if ($requestedToolVersion) { $requestedToolVersion } else { "None" }
$versionRequestedIcon = if ($requestedToolVersion) { '📌' } else { '🔄' }
Write-InfoLine "Version Requested" $versionRequestedText $versionRequestedIcon

$installRequiredText = if ($installRequired) { "Yes" } else { "No" }
$installRequiredIcon = if ($installRequired) { '🚀' } else { '✅' }
Write-InfoLine "Install Required" $installRequiredText $installRequiredIcon

$decisionReason = @()
if (-not $compilerPath) { $decisionReason += "Compiler not found" }
if ($runtimeIncreased) { $decisionReason += "Runtime version increased" }
if ($requestedToolVersion -and $sentinelVersion -and ($requestedToolVersion -ne $sentinelVersion)) { $decisionReason += "Specific version requested" }
if (-not $existingSentinel -and -not $compilerPath) { $decisionReason += "No previous installation" }

if ($decisionReason.Count -gt 0) {
    Write-InfoLine "Reason" ($decisionReason -join ", ") 'ℹ️'
} else {
    Write-InfoLine "Reason" "Already up to date" 'ℹ️'
}

if ($compilerPath -and -not $runtimeIncreased -and -not $requestedToolVersion) {
    Write-Information "✅ COMPILER STATUS:" -InformationAction Continue
    Write-InfoLine "Status" "Already installed and up to date" '✅'
    $displayVersion = if ($sentinelVersion) { $sentinelVersion } elseif ($installedToolVersion) { $installedToolVersion } elseif ($expectedToolVersion) { $expectedToolVersion } else { "(unknown)" }
    Write-InfoLine "Version" $displayVersion '📦'
    Write-InfoLine "Path" $compilerPath '📁'

    if (-not $existingSentinel -or -not $sentinelPackageId) {
        $sentinelVersionToWrite = $sentinelVersion
        if (-not $sentinelVersionToWrite) { $sentinelVersionToWrite = $installedToolVersion }
        if (-not $sentinelVersionToWrite) { $sentinelVersionToWrite = $expectedToolVersion }
        $sentinelPackageToWrite = if ($sentinelPackageId) { $sentinelPackageId } elseif ($installedPackageId) { $installedPackageId } else { $ToolPackageId }
        if ($sentinelVersionToWrite) {
            Write-Sentinel -Path $sentinelPath -CompilerVersion $sentinelVersionToWrite -Runtime $appRuntime -ToolPath $compilerPath -PackageId $sentinelPackageToWrite
            Write-InfoLine "Sentinel" "Updated" '📋'
        }
    }

    Write-Section 'LinterCop Analyzer'
    Write-Information "🧹 LINTERCOP ANALYZER:" -InformationAction Continue
    Install-LinterCopAnalyzer -CompilerPath $compilerPath

    Write-Section 'Summary'
    Write-Information "✅ Compiler provisioning complete - no updates needed!" -InformationAction Continue
    exit 0
}

if (-not $installRequired) {
    Write-Information "✅ COMPILER STATUS:" -InformationAction Continue
    Write-InfoLine "Status" "Already provisioned" '✅'
    Write-InfoLine "Path" $compilerPath '📁'

    Write-Section 'LinterCop Analyzer'
    Write-Information "🧹 LINTERCOP ANALYZER:" -InformationAction Continue
    Install-LinterCopAnalyzer -CompilerPath $compilerPath

    Write-Section 'Summary'
    Write-Information "✅ Compiler provisioning complete - no updates needed!" -InformationAction Continue
    exit 0
}

Write-Section 'Compiler Installation'

$dotnetArgs = @('tool')
$operation = if ($existingSentinel -or (Get-CompilerPath -ToolsRoot $toolsRoot -ToolVersion $sentinelVersion -PackageIds $candidatePackageIds)) { 'update' } else { 'install' }
$dotnetArgs += $operation
$dotnetArgs += @('--global', $ToolPackageId)
if ($requestedToolVersion) {
    $dotnetArgs += @('--version', $requestedToolVersion)
} else {
    $dotnetArgs += @('--prerelease')
}

Write-Information "🚀 INSTALLATION PROCESS:" -InformationAction Continue
Write-InfoLine "Operation" $operation '⚡'
Write-InfoLine "Package ID" $ToolPackageId '📦'
if ($requestedToolVersion) {
    Write-InfoLine "Version" $requestedToolVersion '🎯'
} else {
    Write-InfoLine "Version" "Latest prerelease" '🎯'
}

try {
    Invoke-DotnetToolCommand -Arguments $dotnetArgs
    Write-InfoLine "Result" "Success" '✅'
} catch {
    if ($dotnetArgs[1] -eq 'update') {
        Write-StatusLine "dotnet tool update failed, retrying with install" '⚠️'
        $installArgs = @('tool', 'install', '--global', $ToolPackageId)
        if ($requestedToolVersion) {
            $installArgs += @('--version', $requestedToolVersion)
        } else {
            $installArgs += @('--prerelease')
        }
        try {
            Invoke-DotnetToolCommand -Arguments $installArgs
            Write-InfoLine "Result" "Success (after retry)" '✅'
        } catch {
            Write-StatusLine "AL compiler package not available in configured feeds. Using existing installation if available." '⚠️'
            if (-not $compilerPath) {
                Write-InfoLine "Result" "Failed" '❌'
                throw "AL compiler not available and cannot be installed from configured feeds."
            }
        }
    } else {
        Write-StatusLine "AL compiler package not available in configured feeds. Using existing installation if available." '⚠️'
        if (-not $compilerPath) {
            Write-InfoLine "Result" "Failed" '❌'
            throw "AL compiler not available and cannot be installed from configured feeds."
        }
    }
}

Write-Section 'Installation Verification'

$resolvedToolInfo = Get-InstalledToolInfo -ToolsRoot $toolsRoot -PackageIds $candidatePackageIds
if (-not $resolvedToolInfo) {
    Write-InfoLine "Verification" "Failed" '❌'
    throw 'Unable to determine installed tool version after provisioning.'
}
$resolvedVersion = [string]$resolvedToolInfo.version
$resolvedPackageId = if ($resolvedToolInfo.packageId) { [string]$resolvedToolInfo.packageId } else { $null }
$compilerPath = Get-CompilerPath -ToolsRoot $toolsRoot -ToolVersion $resolvedVersion -PackageIds $candidatePackageIds
if (-not $compilerPath) {
    Write-InfoLine "Verification" "Failed" '❌'
    throw "Installed tool missing alc executable for version $resolvedVersion"
}

Write-Information "✅ VERIFICATION RESULTS:" -InformationAction Continue
Write-InfoLine "Status" "Success" '✅'
Write-InfoLine "Version" $resolvedVersion '📦'
$displayPackageId = if ($resolvedPackageId) { $resolvedPackageId } else { $ToolPackageId }
Write-InfoLine "Package ID" $displayPackageId '🏷️'
Write-InfoLine "Path" $compilerPath '📁'

if (-not $resolvedPackageId) { $resolvedPackageId = $ToolPackageId }
Write-Sentinel -Path $sentinelPath -CompilerVersion $resolvedVersion -Runtime $appRuntime -ToolPath $compilerPath -PackageId $resolvedPackageId
Write-InfoLine "Sentinel" "Updated" '📋'

Write-Section 'LinterCop Analyzer'

Write-Information "🧹 LINTERCOP ANALYZER:" -InformationAction Continue
Install-LinterCopAnalyzer -CompilerPath $compilerPath

Write-Section 'Summary'

Write-Information "🎉 Compiler installation completed successfully!" -InformationAction Continue
Write-StatusLine "AL compiler is ready for use" '✅'

exit 0
