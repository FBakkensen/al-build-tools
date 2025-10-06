#requires -Version 7.2

<#
.SYNOPSIS
    Run AL tests using ALTestRunner module

.DESCRIPTION
    Executes Business Central AL tests using ALTestRunner.
    Assumes apps are already published to the BC server.

.PARAMETER TestDir
    Directory containing the test app and app.json

.PARAMETER ServerUrl
    BC server URL

.PARAMETER ServerInstance
    BC server instance name

.NOTES
    Uses three-tier configuration resolution:
    1. Parameter → 2. Environment Variable → 3. Default Value

    Extension ID and Name are auto-detected from test app.json.
#>

param(
    [string]$TestDir,
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
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build test)"
    exit 2
}

# =============================================================================
# Three-Tier Configuration Resolution
# Priority: 1. Parameter → 2. Environment Variable → 3. Default
# =============================================================================

$TestDir = ($TestDir | Where-Object { $_ }) ?? ($env:ALBT_TEST_DIR | Where-Object { $_ }) ?? 'test'
$ServerUrl = ($ServerUrl | Where-Object { $_ }) ?? ($env:ALBT_BC_SERVER_URL | Where-Object { $_ }) ?? 'http://bctest'
$ServerInstance = ($ServerInstance | Where-Object { $_ }) ?? ($env:ALBT_BC_SERVER_INSTANCE | Where-Object { $_ }) ?? 'BC'

Write-BuildHeader 'Test Execution Setup'

# Auto-detect extension ID and name from test app.json
$appJson = Get-AppJsonObject $TestDir
if (-not $appJson) {
    Write-BuildMessage -Type Error -Message "app.json not found in test directory: $TestDir"
    exit 1
}

$ExtensionId = $appJson.id
$ExtensionName = $appJson.name

if (-not $ExtensionId) {
    Write-BuildMessage -Type Error -Message "Extension ID not found in test app.json 'id' field."
    exit 1
}

if (-not $ExtensionName) {
    Write-BuildMessage -Type Error -Message "Extension Name not found in test app.json 'name' field."
    exit 1
}

# IMPORTANT: Use absolute path for results like AL Test Runner does
$resultsPath = Join-Path (Get-Location).Path (Join-Path $TestDir '.altestrunner')

$Tenant = ($env:ALBT_BC_TENANT | Where-Object { $_ }) ?? 'default'
$launchConfig = New-BCLaunchConfig -ServerUrl $ServerUrl -ServerInstance $ServerInstance -Tenant $Tenant | ConvertTo-Json -Compress

Write-BuildMessage -Type Info -Message "Test Configuration:"
Write-BuildMessage -Type Detail -Message "Test Directory: $TestDir"
Write-BuildMessage -Type Detail -Message "Extension: $ExtensionName"
Write-BuildMessage -Type Detail -Message "Extension ID: $ExtensionId"
Write-BuildMessage -Type Detail -Message "Server: $ServerUrl/$ServerInstance"
Write-BuildMessage -Type Detail -Message "Results Path: $resultsPath"

# Ensure results directory exists
if (-not (Test-Path $resultsPath)) {
    New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null
    Write-BuildMessage -Type Detail -Message "Results Dir: Created"
}

Write-BuildHeader 'Loading ALTestRunner Module'

# Import ALTestRunner module
$alTestRunnerPath = Get-ALTestRunnerModulePath

if (-not $alTestRunnerPath) {
    Write-BuildMessage -Type Error -Message "ALTestRunner PowerShell module not found."
    Write-BuildMessage -Type Detail -Message "Install the AL Test Runner VS Code extension from:"
    Write-BuildMessage -Type Detail -Message "https://marketplace.visualstudio.com/items?itemName=jamespearson.al-test-runner"
    Write-BuildMessage -Type Detail -Message "Supported VSCode installations: stable (.vscode), insiders (.vscode-insiders)"
    exit 1
}

Write-BuildMessage -Type Detail -Message "Module Path: $($alTestRunnerPath.FullName)"

Import-Module $alTestRunnerPath.FullName -DisableNameChecking -Force
Write-BuildMessage -Type Success -Message "Loaded successfully"

Write-BuildHeader 'Running Tests'

try {
    Push-Location $TestDir

    Write-BuildMessage -Type Step -Message "Executing Tests"
    Write-BuildMessage -Type Detail -Message "Test Suite: All tests"

    # Run tests exactly as AL Test Runner does - with absolute path and code coverage
    Invoke-ALTestRunner -Tests All `
                        -ExtensionId $ExtensionId `
                        -ExtensionName $ExtensionName `
                        -LaunchConfig $launchConfig `
                        -ResultsPath $resultsPath `
                        -GetCodeCoverage

    $exitCode = $LASTEXITCODE

} finally {
    Pop-Location
}

Write-BuildHeader 'Test Execution Complete'

exit $exitCode
