#requires -Version 7.2

<#
.SYNOPSIS
    Provisions locally-built app as a symbol for dependent apps.

.DESCRIPTION
    Copies a freshly-built .app file from a source directory to the symbol cache
    of a target directory, making it available for compilation of dependent apps.

    This is essential for test apps that depend on the main app - the test compiler
    needs access to the just-compiled main app as a symbol.

.PARAMETER SourceAppDir
    Directory containing the built app to provision as a symbol (e.g., "app")

.PARAMETER TargetAppDir
    Directory containing the app that needs the symbol (e.g., "test")

.NOTES
    This script bridges the gap between local compilation and symbol resolution.
    The AL compiler expects symbols in the cache, so we provision fresh builds there.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceAppDir,

    [Parameter(Mandatory=$true)]
    [string]$TargetAppDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# Guard: require invocation via Invoke-Build
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build provision-test-dependencies)"
    exit 2
}

# --- Execution ---
Write-BuildHeader 'Local Symbol Provisioning'

Write-BuildMessage -Type Info -Message "SOURCE APP (Symbol Provider):"
$sourceAppJsonPath = Get-AppJsonPath $SourceAppDir
if (-not $sourceAppJsonPath) {
    Write-Error "Source app.json not found in '$SourceAppDir'"
    exit 1
}
$sourceAppJson = Read-JsonFile -Path $sourceAppJsonPath
Write-BuildMessage -Type Detail -Message "Directory: $SourceAppDir"
Write-BuildMessage -Type Detail -Message "Name: $($sourceAppJson.name)"
Write-BuildMessage -Type Detail -Message "Version: $($sourceAppJson.version)"
Write-BuildMessage -Type Detail -Message "Publisher: $($sourceAppJson.publisher)"

Write-Host ""
Write-BuildMessage -Type Info -Message "TARGET APP (Symbol Consumer):"
$targetAppJsonPath = Get-AppJsonPath $TargetAppDir
if (-not $targetAppJsonPath) {
    Write-Error "Target app.json not found in '$TargetAppDir'"
    exit 1
}
$targetAppJson = Read-JsonFile -Path $targetAppJsonPath
Write-BuildMessage -Type Detail -Message "Directory: $TargetAppDir"
Write-BuildMessage -Type Detail -Message "Name: $($targetAppJson.name)"
Write-BuildMessage -Type Detail -Message "Version: $($targetAppJson.version)"

Write-BuildHeader 'Locating Source App'

$sourceAppPath = Get-OutputPath $SourceAppDir
if (-not $sourceAppPath) {
    Write-Error "Could not determine source app output path from app.json"
    exit 1
}

Write-BuildMessage -Type Detail -Message "Expected Path: $sourceAppPath"

if (-not (Test-Path -LiteralPath $sourceAppPath)) {
    Write-Error "Source app not found at: $sourceAppPath. Build the source app first."
    exit 1
}

$sourceAppFile = Get-Item -LiteralPath $sourceAppPath
Write-BuildMessage -Type Success -Message "Source app found"
$fileSize = if ($sourceAppFile.Length -lt 1024) {
    "{0} bytes" -f $sourceAppFile.Length
} elseif ($sourceAppFile.Length -lt 1048576) {
    "{0:N1} KB" -f ($sourceAppFile.Length / 1024)
} else {
    "{0:N1} MB" -f ($sourceAppFile.Length / 1048576)
}
Write-BuildMessage -Type Detail -Message "Size: $fileSize"

Write-BuildHeader 'Resolving Target Symbol Cache'

$targetCacheInfo = Get-SymbolCacheInfo -AppJson $targetAppJson
$targetCacheDir = $targetCacheInfo.CacheDir
Write-BuildMessage -Type Detail -Message "Cache Path: $targetCacheDir"

Ensure-Directory -Path $targetCacheDir
Write-BuildMessage -Type Success -Message "Cache directory ready"

Write-BuildHeader 'Copying Symbol'

# Construct proper filename for symbol cache
# Pattern: {publisher}_{name}_{version}.app
$symbolFileName = "{0}_{1}_{2}.app" -f $sourceAppJson.publisher, $sourceAppJson.name, $sourceAppJson.version
$targetPath = Join-Path -Path $targetCacheDir -ChildPath $symbolFileName

Write-BuildMessage -Type Detail -Message "Source: $sourceAppPath"
Write-BuildMessage -Type Detail -Message "Target: $targetPath"

try {
    Copy-Item -LiteralPath $sourceAppPath -Destination $targetPath -Force
    Write-BuildMessage -Type Success -Message "Symbol copied successfully"
} catch {
    Write-Error "Failed to copy symbol: $($_.Exception.Message)"
    exit 1
}

# Verify the copy
if (Test-Path -LiteralPath $targetPath) {
    $targetFile = Get-Item -LiteralPath $targetPath
    $targetSize = if ($targetFile.Length -lt 1024) {
        "{0} bytes" -f $targetFile.Length
    } elseif ($targetFile.Length -lt 1048576) {
        "{0:N1} KB" -f ($targetFile.Length / 1024)
    } else {
        "{0:N1} MB" -f ($targetFile.Length / 1048576)
    }
    Write-BuildMessage -Type Detail -Message "Verified Size: $targetSize"
} else {
    Write-Error "Symbol copy verification failed - file not found at target"
    exit 1
}

Write-BuildHeader 'Summary'

Write-BuildMessage -Type Success -Message "Local symbol provisioned successfully!"
Write-BuildMessage -Type Detail -Message "Source App: $($sourceAppJson.name)"
Write-BuildMessage -Type Detail -Message "Target App: $($targetAppJson.name)"
Write-Host ""
Write-BuildMessage -Type Info -Message "The target app can now compile with the latest source app as a dependency."

exit 0