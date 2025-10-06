#requires -Version 7.2

<#
.SYNOPSIS
    Install or update the AL compiler to the latest available version.

.DESCRIPTION
    Installs the latest AL compiler from NuGet using dotnet global tools.
    Uses the "latest compiler only" principle - no runtime-specific versions, no version selection.
    Always downloads the most recent compiler and LinterCop analyzer.

.NOTES
    Optional environment variables:
      - ALBT_TOOL_CACHE_ROOT: override for the default ~/.bc-tool-cache location.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]

param()


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# =============================================================================
# Helper Functions
# =============================================================================

function Get-ToolPackageId {
    # Platform-specific package ID selection
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

function Test-DotnetAvailable {
    try {
        $null = Get-Command -Name 'dotnet' -ErrorAction Stop
        return $true
    } catch {
        return $false
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

function Get-LatestCompilerPath {
    <#
    .SYNOPSIS
        Find the AL compiler executable (alc.exe) in global dotnet tools
    #>
    param([string]$PackageId)

    $globalToolsRoot = Get-DotnetRoot
    $storeRoot = Join-Path -Path $globalToolsRoot -ChildPath '.store'

    if (-not (Test-Path -LiteralPath $storeRoot)) {
        return $null
    }

    $packageDirName = $PackageId.ToLower()
    $packageRoot = Join-Path -Path $storeRoot -ChildPath $packageDirName

    if (-not (Test-Path -LiteralPath $packageRoot)) {
        return $null
    }

    # Search for alc.exe/alc executable
    $toolExecutableNames = @('alc.exe', 'alc')
    $items = Get-ChildItem -Path $packageRoot -Recurse -File -Depth 6 -ErrorAction SilentlyContinue |
        Where-Object { $toolExecutableNames -contains $_.Name }

    $candidate = $items | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

    if ($candidate) {
        return $candidate.FullName
    }

    return $null
}

function Get-InstalledCompilerVersion {
    <#
    .SYNOPSIS
        Get currently installed AL compiler version from dotnet tools
    #>
    param([string]$PackageId)

    try {
        $jsonText = & dotnet tool list --global --format json 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }

        $parsed = $jsonText | ConvertFrom-Json
        if (-not $parsed -or -not $parsed.data) { return $null }

        $packageIdLower = $PackageId.ToLowerInvariant()
        foreach ($entry in $parsed.data) {
            $entryId = if ($entry.packageId) { $entry.packageId.ToString().ToLowerInvariant() } else { $null }
            if ($entryId -eq $packageIdLower) {
                return [string]$entry.version
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Install-LatestCompiler {
    <#
    .SYNOPSIS
        Install or update AL compiler to latest version using dotnet global tool
    #>
    param([string]$PackageId)

    try {
        Write-BuildMessage -Type Step -Message "Installing latest AL compiler from NuGet..."
        Write-BuildMessage -Type Detail -Message "Package: $PackageId"

        # Try install first (will fail if already exists)
        $installArgs = @('tool', 'install', '--global', $PackageId, '--prerelease')
        Write-Information "Executing: dotnet $($installArgs -join ' ')" -InformationAction Continue
        $installOutput = & dotnet @installArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            # Tool exists, update it instead
            Write-BuildMessage -Type Detail -Message "Updating existing installation..."
            $updateArgs = @('tool', 'update', '--global', $PackageId, '--prerelease')
            Write-Information "Executing: dotnet $($updateArgs -join ' ')" -InformationAction Continue
            $updateOutput = & dotnet @updateArgs 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-BuildMessage -Type Error -Message "Install output: $installOutput"
                Write-BuildMessage -Type Error -Message "Update output: $updateOutput"
                throw "dotnet tool install and update both failed with exit code $LASTEXITCODE"
            }
        }

        Write-BuildMessage -Type Success -Message "AL compiler installation complete"
        return $true

    } catch {
        Write-BuildMessage -Type Error -Message "Failed to install compiler: $($_.Exception.Message)"
        return $false
    }
}

function Get-LinterCopDownloadUrl {
    <#
    .SYNOPSIS
        Find matching LinterCop DLL URL for the installed compiler version
    #>
    param([string]$CompilerVersion)

    try {
        # Query GitHub API for latest LinterCop release assets
        $apiUrl = "https://api.github.com/repos/StefanMaron/BusinessCentral.LinterCop/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop

        # Extract version number from compiler version (e.g., "17.0.27.27275-beta" -> "17.0.27.27275-beta")
        $versionPattern = $CompilerVersion -replace '^(\d+\.\d+\.\d+\.\d+.*?)$', '$1'

        # Look for exact version match first
        $matchingAsset = $release.assets | Where-Object {
            $_.name -eq "BusinessCentral.LinterCop.AL-$versionPattern.dll"
        } | Select-Object -First 1

        if ($matchingAsset) {
            Write-Information "Found exact version match: $($matchingAsset.name)" -InformationAction Continue
            return $matchingAsset.browser_download_url
        }

        # Fallback: look for major.minor match (e.g., 17.0.x.y)
        if ($CompilerVersion -match '^(\d+\.\d+)\.') {
            $majorMinor = $matches[1]
            $matchingAsset = $release.assets | Where-Object {
                $_.name -match "^BusinessCentral\.LinterCop\.AL-$majorMinor\."
            } | Sort-Object -Property name -Descending | Select-Object -First 1

            if ($matchingAsset) {
                Write-Information "Found major.minor match: $($matchingAsset.name)" -InformationAction Continue
                return $matchingAsset.browser_download_url
            }
        }

        # Last resort: use generic prerelease if version contains beta/preview
        if ($CompilerVersion -match '(beta|preview|pre|rc)') {
            $genericAsset = $release.assets | Where-Object {
                $_.name -eq "BusinessCentral.LinterCop.AL-PreRelease.dll"
            } | Select-Object -First 1

            if ($genericAsset) {
                Write-Information "Using generic prerelease version" -InformationAction Continue
                return $genericAsset.browser_download_url
            }
        }

        # Final fallback: stable version
        $stableAsset = $release.assets | Where-Object {
            $_.name -eq "BusinessCentral.LinterCop.dll"
        } | Select-Object -First 1

        if ($stableAsset) {
            Write-Information "Using stable version as fallback" -InformationAction Continue
            return $stableAsset.browser_download_url
        }

        return $null
    } catch {
        Write-Warning "Failed to query LinterCop releases: $($_.Exception.Message)"
        return $null
    }
}

function Install-LatestLinterCop {
    <#
    .SYNOPSIS
        Install version-matched LinterCop analyzer to compiler directory
    #>
    param(
        [string]$CompilerDir,
        [string]$CompilerVersion
    )

    if (-not $CompilerDir -or -not (Test-Path $CompilerDir)) {
        Write-Information "Compiler directory not provided or doesn't exist: $CompilerDir" -InformationAction Continue
        return
    }

    try {
        $dllFileName = "BusinessCentral.LinterCop.dll"
        $targetDll = Join-Path -Path $CompilerDir -ChildPath $dllFileName

        if (Test-Path -LiteralPath $targetDll) {
            Write-BuildMessage -Type Success -Message "LinterCop already present"
            Write-BuildMessage -Type Detail -Message "Location: $targetDll"
            return
        }

        # Find matching LinterCop version dynamically
        Write-BuildMessage -Type Step -Message "Finding matching LinterCop version..."
        Write-BuildMessage -Type Detail -Message "Compiler version: $CompilerVersion"

        $linterCopUrl = Get-LinterCopDownloadUrl -CompilerVersion $CompilerVersion

        if (-not $linterCopUrl) {
            Write-BuildMessage -Type Warning -Message "No matching LinterCop version found"
            return
        }

        Write-BuildMessage -Type Step -Message "Downloading LinterCop from GitHub..."
        Write-BuildMessage -Type Detail -Message "URL: $linterCopUrl"

        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Invoke-WebRequest -Uri $linterCopUrl -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
            $fileInfo = Get-Item -LiteralPath $tempFile -ErrorAction Stop
            if ($fileInfo.Length -le 0) { throw 'Downloaded file is empty.' }

            Move-Item -LiteralPath $tempFile -Destination $targetDll -Force
            Write-BuildMessage -Type Success -Message "LinterCop installed"
            Write-BuildMessage -Type Detail -Message "Location: $targetDll"
        } catch {
            Write-BuildMessage -Type Warning -Message "Failed to download LinterCop: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-BuildMessage -Type Warning -Message "Error installing LinterCop: $($_.Exception.Message)"
    }
}

function Write-SentinelFile {
    <#
    .SYNOPSIS
        Write sentinel metadata to track installed compiler
    #>
    param(
        [string]$Path,
        [hashtable]$Metadata
    )

    try {
        $json = $Metadata | ConvertTo-Json -Depth 4
        $json | Set-Content -LiteralPath $Path -Encoding UTF8
        Write-Information "Sentinel file written: $Path" -InformationAction Continue
    } catch {
        Write-Warning "Failed to write sentinel file: $Path - $($_.Exception.Message)"
        throw
    }
}

# =============================================================================
# Main Provisioning Logic
# =============================================================================

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build download-compiler)"
    exit $Exit.Guard
}

Write-BuildHeader 'AL Compiler Provisioning - Latest Version Only'

# Check prerequisites
Write-BuildMessage -Type Step -Message "Checking prerequisites..."
if (-not (Test-DotnetAvailable)) {
    Write-BuildMessage -Type Error -Message "dotnet CLI not found on PATH"
    Write-BuildMessage -Type Detail -Message "Install .NET SDK to provision the AL compiler"
    throw 'dotnet CLI not found on PATH. Install .NET SDK to provision the AL compiler.'
}
Write-BuildMessage -Type Success -Message "dotnet CLI available"

# Get platform-specific package ID
$packageId = Get-ToolPackageId
Write-BuildMessage -Type Info -Message "Package ID: $packageId"

# Setup cache directory
$toolCacheRoot = Get-ToolCacheRoot
$alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
Ensure-Directory -Path $alCacheDir

$sentinelPath = Join-Path -Path $alCacheDir -ChildPath 'sentinel.json'

# Check if we need to install/update
Write-BuildMessage -Type Step -Message "Checking for existing installation..."
$currentVersion = Get-InstalledCompilerVersion -PackageId $packageId

$needsInstall = $false
if (-not $currentVersion) {
    Write-BuildMessage -Type Info -Message "No existing installation found"
    $needsInstall = $true
} else {
    Write-BuildMessage -Type Info -Message "Current version: $currentVersion"
    Write-BuildMessage -Type Info -Message "Checking for updates..."
    $needsInstall = $true  # Always update to latest
}

# Install or update compiler
if ($needsInstall) {
    Write-BuildHeader 'Installing/Updating AL Compiler'
    $installSuccess = Install-LatestCompiler -PackageId $packageId

    if (-not $installSuccess) {
        throw "Failed to install AL compiler"
    }
}

# Find installed compiler executable
Write-BuildMessage -Type Step -Message "Locating compiler executable..."
$compilerPath = Get-LatestCompilerPath -PackageId $packageId

if (-not $compilerPath) {
    throw "Could not locate AL compiler executable after installation. Package: $packageId"
}

Write-BuildMessage -Type Success -Message "Compiler found"
Write-BuildMessage -Type Detail -Message "Path: $compilerPath"

# Get final installed version
$finalVersion = Get-InstalledCompilerVersion -PackageId $packageId
Write-BuildMessage -Type Info -Message "Installed version: $finalVersion"

# Install LinterCop
Write-BuildHeader 'LinterCop Analyzer Installation'
$compilerDir = Split-Path -Parent $compilerPath
Install-LatestLinterCop -CompilerDir $compilerDir -CompilerVersion $finalVersion

# Write sentinel file
Write-BuildMessage -Type Step -Message "Writing sentinel file..."
$sentinel = @{
    compilerVersion = $finalVersion
    toolPath = $compilerPath
    packageId = $packageId
    installationType = 'global-tool'
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    principle = 'latest-only'
}
Write-SentinelFile -Path $sentinelPath -Metadata $sentinel

Write-BuildHeader 'Summary'
Write-BuildMessage -Type Success -Message "AL compiler provisioning complete!"
Write-BuildMessage -Type Detail -Message "Version: $finalVersion"
Write-BuildMessage -Type Detail -Message "Compiler: $compilerPath"
Write-BuildMessage -Type Detail -Message "Sentinel: $sentinelPath"
Write-BuildMessage -Type Detail -Message "Principle: Always latest version (no runtime-specific caching)"

exit 0
