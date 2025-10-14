#requires -Version 7.2

<#
.SYNOPSIS
    Publish an AL app to Business Central server.

.DESCRIPTION
    Publishes a compiled AL app (.app file) to a Business Central server
    using BcContainerHelper PowerShell module.

.PARAMETER AppDir
    Directory containing the app to publish (passed from al.build.ps1)

.PARAMETER ServerUrl
    Business Central server URL (e.g., http://bctest)
    Falls back to $env:ALBT_BC_SERVER_URL, then defaults to 'http://bctest'

.PARAMETER ServerInstance
    Business Central server instance name (e.g., BC)
    Falls back to $env:ALBT_BC_SERVER_INSTANCE, then defaults to 'BC'

.NOTES
    This script requires BcContainerHelper PowerShell module.
    Install: Install-Module BcContainerHelper -Scope CurrentUser
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,

    [string]$ServerUrl,

    [string]$ServerInstance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

# Guard: require invocation via Invoke-Build
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build publish)"
    exit 2
}

Write-BuildHeader 'App Publishing Setup'

# Read app.json to get app details
$appJsonPath = Get-AppJsonPath $AppDir
if (-not $appJsonPath) {
    Write-BuildMessage -Type Error -Message "app.json not found in '$AppDir'"
    exit 1
}

$appJson = Read-JsonFile -Path $appJsonPath

Write-BuildMessage -Type Info -Message "APP INFORMATION"
Write-BuildMessage -Type Detail -Message "Directory: $AppDir"
Write-BuildMessage -Type Detail -Message "Name: $($appJson.name)"
Write-BuildMessage -Type Detail -Message "Version: $($appJson.version)"
Write-BuildMessage -Type Detail -Message "Publisher: $($appJson.publisher)"

# Construct app filename
$appFileName = "{0}_{1}_{2}.app" -f $appJson.publisher, $appJson.name, $appJson.version
$appFilePath = Join-Path -Path $AppDir -ChildPath $appFileName

Write-BuildMessage -Type Info -Message "APP FILE"
Write-BuildMessage -Type Detail -Message "Expected: $appFileName"

if (-not (Test-Path -LiteralPath $appFilePath)) {
    Write-BuildMessage -Type Error -Message "App file not found at: $appFilePath. Build the app first."
    exit 1
}

$appFile = Get-Item -LiteralPath $appFilePath
$fileSize = if ($appFile.Length -lt 1024) {
    "{0} bytes" -f $appFile.Length
} elseif ($appFile.Length -lt 1048576) {
    "{0:N1} KB" -f ($appFile.Length / 1024)
} else {
    "{0:N1} MB" -f ($appFile.Length / 1048576)
}
Write-BuildMessage -Type Detail -Message "Status: Found ($fileSize)"

Write-BuildHeader 'Server Configuration'

# Three-tier resolution: parameter → environment variable → documented default
$resolvedServerUrl = ($ServerUrl | Where-Object { $_ }) ??
                     ($env:ALBT_BC_SERVER_URL | Where-Object { $_ }) ??
                     'http://bctest'

$resolvedServerInstance = ($ServerInstance | Where-Object { $_ }) ??
                          ($env:ALBT_BC_SERVER_INSTANCE | Where-Object { $_ }) ??
                          'BC'

$Tenant = ($env:ALBT_BC_TENANT | Where-Object { $_ }) ?? 'default'

Write-BuildMessage -Type Detail -Message "Server: $resolvedServerUrl/$resolvedServerInstance"
Write-BuildMessage -Type Detail -Message "Tenant: $Tenant"

Write-BuildHeader 'Publishing to BC'

# Use system temp directory for completion tracking (not app directory)
$tempDir = [System.IO.Path]::GetTempPath()
$publishCompletionFile = Join-Path -Path $tempDir -ChildPath "al-publish-$([guid]::NewGuid().ToString('N')).txt"

try {
    Push-Location $AppDir

    Write-BuildMessage -Type Step -Message "Publishing app to BC server"
    Write-BuildMessage -Type Detail -Message "App: $($appJson.name)"
    Write-BuildMessage -Type Detail -Message "File: $appFileName"

    # Load BcContainerHelper and prepare credentials
    Import-BCContainerHelper
    $Credential = Get-BCCredential -Username $env:ALBT_BC_CONTAINER_USERNAME -Password $env:ALBT_BC_CONTAINER_PASSWORD
    $ContainerName = ($env:ALBT_BC_CONTAINER_NAME | Where-Object { $_ }) ?? 'bctest'

    Publish-BcContainerApp -containerName $ContainerName `
                          -appFile $appFileName `
                          -skipVerification `
                          -sync `
                          -syncMode ForceSync `
                          -install `
                          -useDevEndpoint `
                          -credential $Credential

    Write-BuildMessage -Type Success -Message "Published successfully"
} catch {
    Write-BuildMessage -Type Error -Message "Failed to publish app: $_"
    exit 1
} finally {
    Pop-Location

    # Clean up completion file
    if (Test-Path $publishCompletionFile) {
        Remove-Item $publishCompletionFile -Force -ErrorAction SilentlyContinue
    }
}

Write-BuildHeader 'Summary'

Write-BuildMessage -Type Success -Message "App published successfully to BC server!"
Write-BuildMessage -Type Detail -Message "App: $($appJson.name)"
Write-BuildMessage -Type Detail -Message "Version: $($appJson.version)"
Write-BuildMessage -Type Info -Message "The app is now available on the BC server for use and testing."

exit 0