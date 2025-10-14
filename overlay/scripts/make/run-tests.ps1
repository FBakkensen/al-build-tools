#requires -Version 7.2

<#
.SYNOPSIS
    Run AL tests using BcContainerHelper module

.DESCRIPTION
    Executes Business Central AL tests using BcContainerHelper.
    Assumes apps are already published to the BC server.

.PARAMETER TestDir
    Directory containing the test app and app.json

.PARAMETER ServerUrl
    BC server URL

.PARAMETER ServerInstance
    BC server instance name

.NOTES
    This script requires BcContainerHelper PowerShell module.
    Install: Install-Module BcContainerHelper -Scope CurrentUser

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

# Local results path (where we want the final results)
$localResultsPath = Join-Path (Get-Location).Path (Join-Path $TestDir 'TestResults')
$localResultFile = Join-Path $localResultsPath 'last.xml'

$Tenant = ($env:ALBT_BC_TENANT | Where-Object { $_ }) ?? 'default'
$ContainerName = ($env:ALBT_BC_CONTAINER_NAME | Where-Object { $_ }) ?? 'bctest'

# Container-shared path (dynamically discovered from container configuration)
# Get shared folders from container and select appropriate one
Import-BCContainerHelper
$sharedFolders = Get-BcContainerSharedFolders -containerName $ContainerName

# Priority 1: Container-specific path (contains container name - best for isolation)
$sharedBaseFolder = $sharedFolders.Keys | Where-Object { $_ -like "*$ContainerName*" } | Select-Object -First 1

# Priority 2: ProgramData path (generally writable and available)
if (-not $sharedBaseFolder) {
    $sharedBaseFolder = $sharedFolders.Keys | Where-Object { $_ -like '*ProgramData*' } | Select-Object -First 1
}

# Priority 3: First available shared folder as last resort
if (-not $sharedBaseFolder) {
    $sharedBaseFolder = $sharedFolders.Keys | Select-Object -First 1
}

# Fail fast if no shared folders exist
if (-not $sharedBaseFolder) {
    Write-BuildMessage -Type Error -Message "No shared folders found for container $ContainerName"
    Write-BuildMessage -Type Detail -Message "Container must have at least one shared folder to write test results"
    exit 1
}

# Create TestResults subdirectory in shared folder
$sharedResultsPath = Join-Path $sharedBaseFolder 'TestResults'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sharedResultFile = Join-Path $sharedResultsPath "test-results-$timestamp.xml"

Write-BuildMessage -Type Info -Message "Test Configuration:"
Write-BuildMessage -Type Detail -Message "Test Directory: $TestDir"
Write-BuildMessage -Type Detail -Message "Extension: $ExtensionName"
Write-BuildMessage -Type Detail -Message "Extension ID: $ExtensionId"
Write-BuildMessage -Type Detail -Message "Server: $ServerUrl/$ServerInstance"
Write-BuildMessage -Type Detail -Message "Container: $ContainerName"
Write-BuildMessage -Type Detail -Message "Tenant: $Tenant"
Write-BuildMessage -Type Detail -Message "Shared folder (base): $sharedBaseFolder"
Write-BuildMessage -Type Detail -Message "Results Path (local): $localResultsPath"
Write-BuildMessage -Type Detail -Message "Results Path (shared): $sharedResultsPath"

# Ensure directories exist
if (-not (Test-Path $localResultsPath)) {
    New-Item -ItemType Directory -Path $localResultsPath -Force | Out-Null
    Write-BuildMessage -Type Detail -Message "Local results dir: Created"
}

if (-not (Test-Path $sharedResultsPath)) {
    New-Item -ItemType Directory -Path $sharedResultsPath -Force | Out-Null
    Write-BuildMessage -Type Detail -Message "Shared results dir: Created"
}

Write-BuildHeader 'Running Tests'

$testExecutionSucceeded = $false
try {
    Write-BuildMessage -Type Step -Message "Executing Tests"
    Write-BuildMessage -Type Detail -Message "Test Suite: All tests"

    # Get credentials (BcContainerHelper already loaded earlier for path discovery)
    $Credential = Get-BCCredential -Username $env:ALBT_BC_CONTAINER_USERNAME -Password $env:ALBT_BC_CONTAINER_PASSWORD

    # Run tests using BcContainerHelper with shared path
    # Run all tests for this extension (no -testSuite or -testCodeunit filters)
    # Don't use -AppendToXUnitResultFile - we want fresh results each time
    Run-TestsInBcContainer -containerName $ContainerName `
                          -tenant $Tenant `
                          -credential $Credential `
                          -extensionId $ExtensionId `
                          -XUnitResultFileName $sharedResultFile `
                          -returnTrueIfAllPassed

    $testExecutionSucceeded = $true
    Write-BuildMessage -Type Success -Message "Test execution completed"

} catch {
    Write-BuildMessage -Type Error -Message "Test execution failed: $_"
}

# Copy results from shared location to local location
Write-BuildHeader 'Copying Test Results'

if ($testExecutionSucceeded) {
    if (Test-Path -LiteralPath $sharedResultFile) {
        Write-BuildMessage -Type Step -Message "Copying results from shared location"
        Write-BuildMessage -Type Detail -Message "Source: $sharedResultFile"
        Write-BuildMessage -Type Detail -Message "Target: $localResultFile"

        Copy-Item -LiteralPath $sharedResultFile -Destination $localResultFile -Force

        if (Test-Path -LiteralPath $localResultFile) {
            Write-BuildMessage -Type Success -Message "Results copied successfully"

            # Clean up shared location
            Remove-Item -LiteralPath $sharedResultFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-BuildMessage -Type Error -Message "Failed to copy results file to local location"
        }
    } else {
        Write-BuildMessage -Type Error -Message "Results file not found in shared location: $sharedResultFile"
        Write-BuildMessage -Type Detail -Message "Tests may have failed to run or container path is not correctly mounted"
    }
} else {
    Write-BuildMessage -Type Warning -Message "Skipping results copy due to test execution failure"
}

Write-BuildHeader 'Test Execution Complete'

# -----------------------------------------------------------------------------
# Test Summary (parse XUnit results XML)
# -----------------------------------------------------------------------------
$exitCode = 0

if (-not $testExecutionSucceeded) {
    Write-BuildHeader 'Summary'
    Write-BuildMessage -Type Error -Message "Test execution failed - no results to parse"
    exit 1
}

if (-not (Test-Path -LiteralPath $localResultFile)) {
    Write-BuildHeader 'Summary'
    Write-BuildMessage -Type Error -Message "Results file not found: $localResultFile"
    Write-BuildMessage -Type Detail -Message "Tests may have failed to run or results were not copied successfully"
    exit 1
}

try {
    Write-BuildHeader 'Summary'

    [xml]$doc = Get-Content -LiteralPath $localResultFile -Raw

    $assemblies = @($doc.assemblies.assembly)
    $total = 0; $passed = 0; $failed = 0; $skipped = 0; $duration = 0.0

    foreach ($asm in $assemblies) {
        $total   += [int]$asm.total
        $passed  += [int]$asm.passed
        $failed  += [int]$asm.failed
        $skipped += [int]$asm.skipped
        if ($asm.time) { $duration += [double]::Parse([string]$asm.time, [System.Globalization.CultureInfo]::InvariantCulture) }
    }

    $durationFormatted = if ($duration -ge 60) {
        $ts = [TimeSpan]::FromSeconds([double]$duration)
        $ts.ToString('mm\:ss') + ' min'
    } elseif ($duration -gt 0) {
        ('{0:N3} s' -f $duration)
    } else { '—' }

    $summaryLine = "Total: $total  Passed: $passed  Failed: $failed  Skipped: $skipped  Duration: $durationFormatted"

    if ($failed -gt 0) {
        Write-BuildMessage -Type Error   -Message 'Tests failed'
        Write-BuildMessage -Type Info    -Message $summaryLine
        $exitCode = 1
    } else {
        Write-BuildMessage -Type Success -Message 'All tests passed'
        Write-BuildMessage -Type Info    -Message $summaryLine
        $exitCode = 0
    }

    # List failed tests (up to 20) for quick visibility
    $failedTests = @($doc.assemblies.assembly.collection.test | Where-Object { $_.result -and $_.result -notin @('Pass', 'Passed') })
    if ($failedTests.Count -gt 0) {
        $maxToShow = 20
        Write-BuildMessage -Type Step -Message ("Failed Tests ({0})" -f $failedTests.Count)
        $i = 0
        foreach ($t in $failedTests) {
            if ($i -ge $maxToShow) { break }
            $name = if ($t.name) { [string]$t.name } elseif ($t.method) { [string]$t.method } else { '(unnamed test)' }
            Write-BuildMessage -Type Detail -Message $name
            $i++
        }
        if ($failedTests.Count -gt $maxToShow) {
            Write-BuildMessage -Type Detail -Message ("…and {0} more" -f ($failedTests.Count - $maxToShow))
        }
    }

    Write-BuildMessage -Type Detail -Message ("Results File: {0}" -f (Resolve-Path -LiteralPath $localResultFile).Path)

} catch {
    Write-BuildMessage -Type Error -Message 'Failed to parse test results'
    Write-BuildMessage -Type Detail -Message $_.Exception.Message
    $exitCode = 1
}

exit $exitCode
