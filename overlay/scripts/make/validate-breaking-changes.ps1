#requires -Version 7.2

<#
.SYNOPSIS
    Validate AL app against previous release for breaking changes

.DESCRIPTION
    Downloads the latest release from GitHub using gh CLI and runs Run-AlValidation
    to check for breaking changes between the current build and the
    previous release. Uses AppSourceCop.json for affixes and supported
    countries configuration.

.NOTES
    Requires BcContainerHelper PowerShell module.
    Requires Docker for containerized validation.
    Requires GitHub CLI (gh) for release download.
    Must be called via Invoke-Build.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppDir
)

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# Get exit codes
$Exit = Get-ExitCode

# Guard: require invocation via Invoke-Build
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "This script must be called via Invoke-Build"
    Write-Output "Run: Invoke-Build validate-breaking-changes"
    exit $Exit.Guard
}

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

Write-BuildHeader 'Configuration'

# Resolve app directory to absolute path
$absoluteAppDir = (Resolve-Path -Path $AppDir).Path
Write-BuildMessage -Type Detail -Message "App Directory: $absoluteAppDir"

# Read validate current setting from environment
$validateCurrent = $env:ALBT_VALIDATE_CURRENT -eq "1"
Write-BuildMessage -Type Detail -Message "Validate Current: $validateCurrent"

# -----------------------------------------------------------------------------
# LOAD APPSOURCECOP.JSON
# -----------------------------------------------------------------------------

Write-BuildHeader 'AppSourceCop Configuration'

$appSourceCopPath = Join-Path $absoluteAppDir "AppSourceCop.json"
if (-not (Test-Path $appSourceCopPath)) {
    Write-BuildMessage -Type Error -Message "AppSourceCop.json not found at: $appSourceCopPath"
    Write-Error "[ERROR] AppSourceCop.json is required for validation"
    exit $Exit.Contract
}

Write-BuildMessage -Type Step -Message "Loading AppSourceCop.json..."
$appSourceCop = Get-Content $appSourceCopPath | ConvertFrom-Json

# Extract affixes
$affixes = $appSourceCop.mandatoryAffixes
if (-not $affixes -or $affixes.Count -eq 0) {
    Write-BuildMessage -Type Error -Message "No mandatoryAffixes found in AppSourceCop.json"
    Write-Error "[ERROR] mandatoryAffixes are required for validation"
    exit $Exit.Contract
}
Write-BuildMessage -Type Detail -Message "Affixes: $($affixes -join ', ')"

# Extract supported countries
$supportedCountries = $appSourceCop.supportedCountries
if (-not $supportedCountries -or $supportedCountries.Count -eq 0) {
    Write-BuildMessage -Type Error -Message "No supportedCountries found in AppSourceCop.json"
    Write-Error "[ERROR] supportedCountries are required for validation"
    exit $Exit.Contract
}
Write-BuildMessage -Type Detail -Message "Supported Countries: $($supportedCountries -join ', ')"

# -----------------------------------------------------------------------------
# FIND CURRENT APP
# -----------------------------------------------------------------------------

Write-BuildHeader 'Current App'

Write-BuildMessage -Type Step -Message "Locating compiled app..."
$currentAppPath = Get-OutputPath $absoluteAppDir

if (-not $currentAppPath) {
    Write-BuildMessage -Type Error -Message "Could not determine app output path"
    Write-BuildMessage -Type Detail -Message "Verify app.json contains valid name, version, and publisher"
    Write-Error "[ERROR] Could not determine app output path"
    exit $Exit.Contract
}

if (-not (Test-Path $currentAppPath -PathType Leaf)) {
    Write-BuildMessage -Type Error -Message "App file not found: $currentAppPath"
    Write-BuildMessage -Type Detail -Message "Run 'Invoke-Build build' first to compile the app"
    Write-Error "[ERROR] Current app not found"
    exit $Exit.Contract
}

$currentApp = Get-Item -LiteralPath $currentAppPath
Write-BuildMessage -Type Detail -Message "App: $($currentApp.Name)"
Write-BuildMessage -Type Detail -Message "Path: $($currentApp.FullName)"
Write-BuildMessage -Type Detail -Message "Size: $([math]::Round($currentApp.Length / 1MB, 2)) MB"

# -----------------------------------------------------------------------------
# DOWNLOAD PREVIOUS RELEASE
# -----------------------------------------------------------------------------

Write-BuildHeader 'Previous Release'

# Get repository from git remote
Write-BuildMessage -Type Step -Message "Detecting repository..."
$gitRemote = git remote get-url origin 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-BuildMessage -Type Error -Message "Failed to get git remote"
    Write-Error "[ERROR] Could not determine repository from git remote"
    exit $Exit.Integration
}

# Extract owner/repo from remote URL
if ($gitRemote -match 'github\.com[:/](.+?)(?:\.git)?$') {
    $repo = $matches[1]
    Write-BuildMessage -Type Detail -Message "Repository: $repo"
} else {
    Write-BuildMessage -Type Error -Message "Could not parse GitHub repository from: $gitRemote"
    Write-Error "[ERROR] Invalid GitHub remote URL"
    exit $Exit.Integration
}

# Get latest release info using gh CLI
Write-BuildMessage -Type Step -Message "Checking for latest release..."

try {
    # gh CLI may output debug lines starting with *, filter those out
    $releaseJson = gh release view --repo $repo --json tagName,assets | Where-Object { $_ -notmatch '^\*' } | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-BuildMessage -Type Error -Message "Failed to get release information"
        Write-Error "[ERROR] No releases found or gh CLI authentication required"
        exit $Exit.Integration
    }

    $release = $releaseJson | ConvertFrom-Json
    $tag = $release.tagName
    Write-BuildMessage -Type Detail -Message "Latest Release: $tag"

} catch {
    Write-BuildMessage -Type Error -Message "Failed to query GitHub releases: $($_.Exception.Message)"
    Write-Error "[ERROR] Failed to query GitHub releases: $($_.Exception.Message)"
    exit $Exit.Integration
}

# Check for assets (either .app files or .zip files containing apps)
Write-BuildMessage -Type Step -Message "Checking for app assets..."
$appAssets = $release.assets | Where-Object { $_.name -like "*.app" }
$zipAssets = $release.assets | Where-Object { $_.name -like "*-Apps-*.zip" -or $_.name -like "*-Dependencies-*.zip" }

if ($appAssets.Count -eq 0 -and $zipAssets.Count -eq 0) {
    $availableAssets = ($release.assets | ForEach-Object { $_.name }) -join ', '
    Write-BuildMessage -Type Error -Message "No .app or .zip files found in release $tag"
    Write-BuildMessage -Type Detail -Message "Available assets: $availableAssets"
    Write-Error "[ERROR] No apps found in release"
    exit $Exit.Contract
}

if ($appAssets.Count -gt 0) {
    Write-BuildMessage -Type Detail -Message "Found $($appAssets.Count) .app file(s) in release"
}
if ($zipAssets.Count -gt 0) {
    Write-BuildMessage -Type Detail -Message "Found $($zipAssets.Count) .zip file(s) in release"
}

# Create temp directory for download
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "alvalidation-$(New-Guid)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-BuildMessage -Type Detail -Message "Temp Directory: $tempDir"

# Download assets using gh CLI
Write-BuildMessage -Type Step -Message "Downloading release assets..."

try {
    # Download .app files if present
    if ($appAssets.Count -gt 0) {
        gh release download $tag --repo $repo --pattern "*.app" --dir $tempDir --clobber 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-BuildMessage -Type Error -Message "Failed to download .app assets"
            Write-Error "[ERROR] Failed to download .app assets"
            exit $Exit.Integration
        }
    }

    # Download .zip files if present
    if ($zipAssets.Count -gt 0) {
        gh release download $tag --repo $repo --pattern "*-Apps-*.zip" --dir $tempDir --clobber 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-BuildMessage -Type Error -Message "Failed to download zip assets"
            Write-Error "[ERROR] Failed to download zip assets"
            exit $Exit.Integration
        }

        gh release download $tag --repo $repo --pattern "*-Dependencies-*.zip" --dir $tempDir --clobber 2>&1 | Out-Null
        # Dependencies might not exist, so don't fail on this
    }

    # Extract .app files from .zip archives
    $zipFiles = Get-ChildItem -Path $tempDir -Filter "*.zip" -File
    if ($zipFiles.Count -gt 0) {
        Write-BuildMessage -Type Step -Message "Extracting .app files from zip archives..."
        foreach ($zipFile in $zipFiles) {
            Write-BuildMessage -Type Detail -Message "Extracting: $($zipFile.Name)"
            Expand-Archive -Path $zipFile.FullName -DestinationPath $tempDir -Force
            Remove-Item -Path $zipFile.FullName -Force
        }
    }

    # Get all downloaded .app files
    $downloadedApps = Get-ChildItem -Path $tempDir -Filter "*.app" -File -Recurse

    if ($downloadedApps.Count -eq 0) {
        Write-BuildMessage -Type Error -Message "No .app files found after download and extraction"
        Write-Error "[ERROR] Download completed but no .app files found"
        exit $Exit.Integration
    }

    Write-BuildMessage -Type Success -Message "Downloaded $($downloadedApps.Count) app(s) successfully"
    foreach ($app in $downloadedApps) {
        Write-BuildMessage -Type Detail -Message "$($app.Name) ($([math]::Round($app.Length / 1MB, 2)) MB)"
    }

} catch {
    Write-BuildMessage -Type Error -Message "Failed to download: $($_.Exception.Message)"
    Write-Error "[ERROR] Failed to download: $($_.Exception.Message)"
    exit $Exit.Integration
}

# -----------------------------------------------------------------------------
# SEPARATE MAIN APP FROM DEPENDENCIES
# -----------------------------------------------------------------------------

Write-BuildHeader 'App Classification'

# Get current app name from app.json to identify main app
$appJsonPath = Join-Path $absoluteAppDir "app.json"
$appJson = Get-Content $appJsonPath -Raw | ConvertFrom-Json

# Build expected main app filename pattern: publisher_name_*.app
$mainAppPattern = "$($appJson.publisher)_$($appJson.name)_*.app"
Write-BuildMessage -Type Step -Message "Identifying main app..."
Write-BuildMessage -Type Detail -Message "Pattern: $mainAppPattern"

# Find main app
$previousMainApp = $downloadedApps | Where-Object { $_.Name -like $mainAppPattern } | Select-Object -First 1

if (-not $previousMainApp) {
    Write-BuildMessage -Type Error -Message "Could not find main app in downloaded files"
    Write-BuildMessage -Type Detail -Message "Expected pattern: $mainAppPattern"
    Write-BuildMessage -Type Detail -Message "Downloaded files: $($downloadedApps.Name -join ', ')"
    Write-Error "[ERROR] Main app not found in release"
    exit $Exit.Contract
}

Write-BuildMessage -Type Success -Message "Main app: $($previousMainApp.Name)"

# All other apps are dependencies
$dependencyApps = $downloadedApps | Where-Object { $_.FullName -ne $previousMainApp.FullName }

if ($dependencyApps.Count -gt 0) {
    Write-BuildMessage -Type Step -Message "Dependency apps:"
    foreach ($dep in $dependencyApps) {
        Write-BuildMessage -Type Detail -Message "$($dep.Name)"
    }
} else {
    Write-BuildMessage -Type Detail -Message "No dependency apps found"
}

# -----------------------------------------------------------------------------
# LOAD BCCONTAINERHELPER
# -----------------------------------------------------------------------------

Write-BuildHeader 'Loading BcContainerHelper Module'

# Import BcContainerHelper module using existing function
Import-BCContainerHelper

# -----------------------------------------------------------------------------
# RUN VALIDATION
# -----------------------------------------------------------------------------

Write-BuildHeader 'AL Validation'

Write-BuildMessage -Type Step -Message "Running Run-AlValidation..."
Write-BuildMessage -Type Detail -Message "Current App: $($currentApp.Name)"
Write-BuildMessage -Type Detail -Message "Previous App: $($previousMainApp.Name)"

# Build validation parameters
$validationParams = @{
    apps = @($currentApp.FullName)
    previousApps = @($previousMainApp.FullName)
    affixes = $affixes
    countries = $supportedCountries
    skipVerification = $true
}

# Add dependency apps if present
if ($dependencyApps.Count -gt 0) {
    $validationParams['installApps'] = @($dependencyApps | ForEach-Object { $_.FullName })
    Write-BuildMessage -Type Detail -Message "Dependencies: $($dependencyApps.Count) app(s)"
}

# Add validateCurrent if enabled
if ($validateCurrent) {
    $validationParams['validateCurrent'] = $true
    Write-BuildMessage -Type Detail -Message "Validate Current: Enabled"
}

Write-BuildMessage -Type Detail -Message "Skip Verification: Enabled (unsigned app)"

try {
    Run-AlValidation @validationParams

    Write-BuildMessage -Type Success -Message "Validation completed successfully"

} catch {
    Write-BuildMessage -Type Error -Message "Validation failed: $($_.Exception.Message)"
    Write-Error "[ERROR] Validation failed: $($_.Exception.Message)"
    exit $Exit.Analysis
} finally {
    # Cleanup temp directory
    Write-BuildMessage -Type Step -Message "Cleaning up..."
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-BuildMessage -Type Detail -Message "Temp directory removed"
    }
}

Write-BuildHeader 'Validation Complete'
Write-BuildMessage -Type Success -Message "No breaking changes detected!"

exit 0
