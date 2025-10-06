#requires -Version 7.2

<#
.SYNOPSIS
    Create and configure Business Central Docker container

.DESCRIPTION
    Sets up a new BC Docker container using BcContainerHelper.
    Uses three-tier configuration resolution for all parameters.
    Automatically installs AL Test Runner Service.

.NOTES
    Uses three-tier configuration resolution:
    1. Parameter → 2. Environment Variable → 3. Default Value

    Requires BcContainerHelper PowerShell module.
#>

param(
    [string]$ContainerName,
    [string]$ContainerUsername,
    [string]$ContainerPassword,
    [string]$ContainerAuth,
    [string]$ArtifactCountry,
    [string]$ArtifactSelect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# Guard: require invocation via Invoke-Build
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build new-bc-container)"
    exit 2
}

# =============================================================================
# Three-Tier Configuration Resolution
# Priority: 1. Parameter → 2. Environment Variable → 3. Default
# =============================================================================

$ContainerName = ($ContainerName | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_NAME | Where-Object { $_ }) ?? 'bctest'
$ContainerUsername = ($ContainerUsername | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_USERNAME | Where-Object { $_ }) ?? 'admin'
$ContainerPassword = ($ContainerPassword | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_PASSWORD | Where-Object { $_ }) ?? 'P@ssw0rd'
$ContainerAuth = ($ContainerAuth | Where-Object { $_ }) ?? ($env:ALBT_BC_CONTAINER_AUTH | Where-Object { $_ }) ?? 'UserPassword'
$ArtifactCountry = ($ArtifactCountry | Where-Object { $_ }) ?? ($env:ALBT_BC_ARTIFACT_COUNTRY | Where-Object { $_ }) ?? 'w1'
$ArtifactSelect = ($ArtifactSelect | Where-Object { $_ }) ?? ($env:ALBT_BC_ARTIFACT_SELECT | Where-Object { $_ }) ?? 'Latest'

Write-BuildHeader 'BC Container Setup'

Write-BuildMessage -Type Info -Message "CONTAINER CONFIGURATION"
Write-BuildMessage -Type Detail -Message "Container Name: $ContainerName"
Write-BuildMessage -Type Detail -Message "Username: $ContainerUsername"
Write-BuildMessage -Type Detail -Message "Authentication: $ContainerAuth"
Write-BuildMessage -Type Detail -Message "Artifact Country: $ArtifactCountry"
Write-BuildMessage -Type Detail -Message "Artifact Selection: $ArtifactSelect"

Write-BuildHeader 'Loading BcContainerHelper'

# Import BcContainerHelper module
Import-BCContainerHelper

Write-BuildHeader 'Retrieving BC Artifact'

Write-BuildMessage -Type Step -Message "Getting BC artifact URL"
Write-BuildMessage -Type Detail -Message "Type: OnPrem"
Write-BuildMessage -Type Detail -Message "Country: $ArtifactCountry"
Write-BuildMessage -Type Detail -Message "Version: $ArtifactSelect"

$artifactUrl = Get-BcArtifactUrl -type 'OnPrem' -country $ArtifactCountry -select $ArtifactSelect

Write-BuildMessage -Type Success -Message "Artifact URL retrieved"
Write-BuildMessage -Type Detail -Message "URL: $artifactUrl"

Write-BuildHeader 'Creating BC Container'

# Create credential object
$credential = Get-BCCredential -Username $ContainerUsername -Password $ContainerPassword

Write-BuildMessage -Type Step -Message "Creating container '$ContainerName'"
Write-BuildMessage -Type Detail -Message "This may take several minutes..."

try {
    New-BcContainer `
        -accept_eula `
        -containerName $ContainerName `
        -credential $credential `
        -auth $ContainerAuth `
        -artifactUrl $artifactUrl `
        -includeTestToolkit `
        -includeTestLibrariesOnly `
        -dns '8.8.8.8' `
        -useBestContainerOS `
        -isolation 'process' `
        -updateHosts

    Write-BuildMessage -Type Success -Message "Container created successfully"
} catch {
    Write-BuildMessage -Type Error -Message "Failed to create container: $_"
    exit 1
}

Write-BuildHeader 'Installing AL Test Runner Service'

Write-BuildMessage -Type Step -Message "Downloading AL Test Runner Service app"
$tempDir = New-TemporaryDirectory
$testRunnerUrl = 'https://github.com/jimmymcp/test-runner-service/raw/master/James%20Pearson_Test%20Runner%20Service.app'
$testRunnerAppPath = Join-Path $tempDir 'Test Runner Service.app'

Write-BuildMessage -Type Detail -Message "URL: $testRunnerUrl"
Write-BuildMessage -Type Detail -Message "Temp directory: $tempDir"

try {
    Invoke-WebRequest -Uri $testRunnerUrl -OutFile $testRunnerAppPath -UseBasicParsing
    Write-BuildMessage -Type Success -Message "Downloaded Test Runner Service app"
    Write-BuildMessage -Type Detail -Message "File: $testRunnerAppPath"

    Write-BuildMessage -Type Step -Message "Publishing Test Runner Service to container"
    Write-BuildMessage -Type Detail -Message "This may take a minute..."

    Publish-BcContainerApp -containerName $ContainerName `
                           -appFile $testRunnerAppPath `
                           -skipVerification `
                           -sync `
                           -install `
                           -credential $credential

    Write-BuildMessage -Type Success -Message "Test Runner Service installed successfully"
} catch {
    Write-BuildMessage -Type Error -Message "Failed to install Test Runner Service: $_"
    exit 1
} finally {
    # Clean up temp directory
    if (Test-Path $tempDir) {
        Write-BuildMessage -Type Detail -Message "Cleaning up temporary files"
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-BuildHeader 'Summary'

Write-BuildMessage -Type Success -Message "BC container '$ContainerName' is ready!"
Write-BuildMessage -Type Detail -Message "Container Name: $ContainerName"
Write-BuildMessage -Type Detail -Message "Authentication: $ContainerAuth"
Write-BuildMessage -Type Detail -Message "Credentials: $ContainerUsername / $ContainerPassword"
Write-BuildMessage -Type Detail -Message "AL Test Runner Service: Installed"
Write-BuildMessage -Type Info -Message "Use this container for publishing and testing AL apps."

exit 0
