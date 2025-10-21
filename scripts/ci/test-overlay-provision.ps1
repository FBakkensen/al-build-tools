#requires -Version 7.2

<#
.SYNOPSIS
    Validates overlay provision tasks within a Docker container environment.

.DESCRIPTION
    Tests Invoke-Build provision workflow (download-compiler, download-symbols) in a
    clean Windows container with pre-installed infrastructure. Validates compiler
    installation and symbol cache integrity using real BC 27 project with dependencies.

.PARAMETER Help
    Display this help message and exit.

.EXAMPLE
    pwsh -File scripts/ci/test-overlay-provision.ps1 -Verbose

.PARAMETER Environment Variables
    ALBT_TEST_BASE_IMAGE       - Base image tag (default: albt-test-base:windows-latest)
    ALBT_TEST_KEEP_CONTAINER   - Set to '1' to skip auto-remove container for debugging
    ALBT_TEST_PROVISION_TIMEOUT - Provision timeout in seconds (default: 300)
    VERBOSE                    - Set to enable verbose logging

.OUTPUTS
    Artifacts:
      out/test-overlay-provision/provision.transcript.txt  - PowerShell transcript
      out/test-overlay-provision/summary.json              - Execution summary
      out/test-overlay-provision/provision.log             - Container provisioning details

.EXIT CODES
    0 - Success: Provision tasks completed and validated
    1 - General Error: Provision failed or validation failed
    6 - MissingTool: Docker not available
#>

[CmdletBinding()]
param(
    [switch]$Help
)

if ($Help -or ($args -contains '-?')) {
    Write-Host @"
SYNOPSIS
    Validates overlay provision tasks within a Docker container environment.

USAGE
    pwsh -File scripts/ci/test-overlay-provision.ps1 [OPTIONS]

OPTIONS
    -Help, -?              Display this help message and exit.

ENVIRONMENT VARIABLES
    ALBT_TEST_BASE_IMAGE            - Base image tag (default: albt-test-base:windows-latest)
    ALBT_TEST_KEEP_CONTAINER        - Set to '1' to skip auto-remove container for debugging
    ALBT_TEST_PROVISION_TIMEOUT     - Provision timeout in seconds (default: 300)
    VERBOSE                         - Set to enable verbose logging

EXIT CODES
    0 - Success: Provision tasks completed and validated
    1 - General Error: Provision failed or validation failed
    6 - MissingTool: Docker not available

ARTIFACTS
    out/test-overlay-provision/provision.transcript.txt  - PowerShell transcript
    out/test-overlay-provision/summary.json              - Execution summary
    out/test-overlay-provision/provision.log             - Container log

"@
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION & GLOBALS
# ============================================================================

$script:DefaultBaseImage = 'albt-test-base:windows-latest'
$script:OutputDir = 'out/test-overlay-provision'
$script:TranscriptFile = 'provision.transcript.txt'
$script:SummaryFile = 'summary.json'
$script:ProvisionLogFile = 'provision.log'
$script:DefaultTimeout = 300  # 5 minutes for symbol downloads
$script:TranscriptPath = $null

$script:ErrorCategoryMap = @{
    'success'           = 0
    'general-error'     = 1
    'missing-tool'      = 6
}

$script:TimedPhases = @{}

# ============================================================================
# SECTION: Logging
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $false)] [ValidateSet('Info', 'Verbose', 'Warning', 'Error')] [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $output = "[$timestamp] $Message"

    switch ($Level) {
        'Verbose' { Write-Verbose $output }
        'Warning' { Write-Warning $output }
        'Error' { Write-Error $output }
        default { Write-Host $output }
    }

    if ($script:TranscriptPath -and (Test-Path $script:TranscriptPath)) {
        Add-Content -Path $script:TranscriptPath -Value $output -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

function Write-ProvisionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $false)] [ref]$ProvisionLogLines,
        [Parameter(Mandatory = $false)] [ValidateSet('Info', 'Warning', 'Error')] [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] $Message"

    switch ($Level) {
        'Warning' { Write-Host $logLine -ForegroundColor Yellow }
        'Error' { Write-Host $logLine -ForegroundColor Red }
        default { Write-Host $logLine }
    }

    if ($ProvisionLogLines) {
        $ProvisionLogLines.Value += $logLine
    }
}

# ============================================================================
# SECTION: Timing
# ============================================================================

function Invoke-TimedPhaseStart {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$PhaseName)

    $script:TimedPhases[$PhaseName] = @{
        'start' = Get-Date
        'end'   = $null
    }
    Write-Verbose "[albt] Phase started: $PhaseName"
}

function Invoke-TimedPhaseStop {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$PhaseName)

    if ($script:TimedPhases.ContainsKey($PhaseName)) {
        $script:TimedPhases[$PhaseName]['end'] = Get-Date
        $duration = [int]($script:TimedPhases[$PhaseName]['end'] - $script:TimedPhases[$PhaseName]['start']).TotalSeconds
        Write-Verbose "[albt] Phase completed: $PhaseName ($duration seconds)"
    }
}

# ============================================================================
# SECTION: Docker & Container
# ============================================================================

function Assert-DockerAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error 'Docker engine not found. Please install Docker Desktop or Docker CLI.'
        $script:ErrorCategory = 'missing-tool'
        exit 6
    }
    Write-Verbose '[albt] Docker engine verified'
}

function Resolve-BaseImage {
    [CmdletBinding()]
    param()

    $image = $env:ALBT_TEST_BASE_IMAGE
    if ([string]::IsNullOrWhiteSpace($image)) {
        $image = $script:DefaultBaseImage
    }
    Write-Verbose "[albt] Using base image: $image"
    return $image
}

function Invoke-ContainerProvisionTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [ref]$ContainerId,
        [ref]$ExitCode,
        [ref]$ContainerOutput,
        [ref]$ProvisionLog
    )

    $randomSuffix = -join ((0..9) + ('a'..'f') | Get-Random -Count 8)
    $containerName = "albt-test-provision-$randomSuffix"
    $provisionLogLines = @()

    Write-ProvisionMessage "[albt] Starting container provisioning: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $overlayPath = Join-Path $repoRoot 'overlay'
    $testdataPath = Join-Path $PSScriptRoot 'testdata-overlay'
    $containerScriptDir = $PSScriptRoot

    if (-not (Test-Path $overlayPath)) {
        throw "Overlay directory not found at $overlayPath"
    }
    if (-not (Test-Path $testdataPath)) {
        throw "Test data directory not found at $testdataPath"
    }

    try {
        $timeout = if ($env:ALBT_TEST_PROVISION_TIMEOUT) { [int]$env:ALBT_TEST_PROVISION_TIMEOUT } else { $script:DefaultTimeout }
        Write-ProvisionMessage "[albt] Timeout: $timeout seconds" -ProvisionLogLines ([ref]$provisionLogLines)

        $runArgs = @(
            'run'
            '--name', $containerName
        )

        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            $runArgs += '--rm'
        }

        $runArgs += @(
            '-v', "${overlayPath}:C:\overlay"
            '-v', "${testdataPath}:C:\testdata"
            '-v', "${containerScriptDir}:C:\test-scripts"
            $Image
            'pwsh.exe'
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', 'C:\test-scripts\container-test-overlay-provision.ps1'
        )

        Write-ProvisionMessage "[albt] Executing container test..." -ProvisionLogLines ([ref]$provisionLogLines)

        $outputLines = New-Object System.Collections.ArrayList
        & docker @runArgs 2>&1 | ForEach-Object {
            Write-Host $_
            [void]$outputLines.Add($_)
        }
        $dockerExitCode = $LASTEXITCODE

        $ExitCode.Value = $dockerExitCode
        $ContainerOutput.Value = $outputLines.ToArray()
        Write-ProvisionMessage "[albt] Container completed with exit code: $($ExitCode.Value)" -ProvisionLogLines ([ref]$provisionLogLines)
    }
    catch {
        Write-ProvisionMessage "Failed to run container: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        $ProvisionLog.Value = $provisionLogLines -join "`n"
        $script:ErrorCategory = 'general-error'
        return $false
    }
    finally {
        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            Remove-ContainerSafely -ContainerName $containerName
        }
        $ProvisionLog.Value = $provisionLogLines -join "`n"
    }

    $ContainerId.Value = $containerName
    return $true
}

function Remove-ContainerSafely {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory = $true)] [string]$ContainerName)

    if ($PSCmdlet.ShouldProcess($ContainerName, 'Remove Docker container')) {
        try {
            Write-Verbose "[albt] Removing container: $ContainerName"
            docker rm -f $ContainerName 2>&1 | Out-Null
        }
        catch {
            Write-Verbose "[albt] Container removal failed or already removed: $_"
        }
    }
}

# ============================================================================
# SECTION: Summary & Artifacts
# ============================================================================

function Start-TestTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $transcriptPath = Join-Path $script:OutputDir $script:TranscriptFile
    $header = @"
================================================================================
PowerShell Transcript Start
StartTime: $(Get-Date -Format 'o')
StartPath: $(Get-Location)
Version: $($PSVersionTable.PSVersion)
================================================================================
"@
    $header | Out-File -Path $transcriptPath -Encoding UTF8 -Force
    return $transcriptPath
}

function New-TestSummary {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [Parameter(Mandatory = $false)] [string]$ContainerId,
        [Parameter(Mandatory = $true)] [DateTime]$StartTime,
        [Parameter(Mandatory = $true)] [DateTime]$EndTime,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $false)] [string]$ErrorSummary = '',
        [Parameter(Mandatory = $false)] [string]$TranscriptPath = '',
        [Parameter(Mandatory = $false)] [hashtable]$TimedPhases = @{}
    )

    $durationSeconds = [int]($EndTime - $StartTime).TotalSeconds
    $success = ($ExitCode -eq 0)

    $summary = @{
        testType          = 'overlay-provision'
        image             = $Image
        startTime         = $StartTime.ToUniversalTime().ToString('o')
        endTime           = $EndTime.ToUniversalTime().ToString('o')
        durationSeconds   = $durationSeconds
        exitCode          = $ExitCode
        success           = $success
        runId             = "run-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString().Substring(0,8))"
    }

    if ($ContainerId) { $summary['containerId'] = $ContainerId }
    if ($ErrorSummary) { $summary['errorSummary'] = $ErrorSummary }
    if ($TranscriptPath) { $summary['logs'] = @{ transcript = $TranscriptPath } }

    if ($TimedPhases.Count -gt 0) {
        $phases = @{}
        foreach ($phaseName in $TimedPhases.Keys) {
            $phase = $TimedPhases[$phaseName]
            if ($phase['end']) {
                $phaseDuration = [int]($phase['end'] - $phase['start']).TotalSeconds
                $phases[$phaseName] = @{
                    'startTime'       = $phase['start'].ToUniversalTime().ToString('o')
                    'endTime'         = $phase['end'].ToUniversalTime().ToString('o')
                    'durationSeconds' = $phaseDuration
                }
            }
        }
        if ($phases.Count -gt 0) { $summary['timedPhases'] = $phases }
    }

    return $summary
}

function Write-TestSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable]$Summary)

    $summaryPath = Join-Path $script:OutputDir $script:SummaryFile

    try {
        $json = ConvertTo-Json -InputObject $Summary -Depth 10
        Set-Content -Path $summaryPath -Value $json -Encoding UTF8 -Force
        Write-Verbose "[albt] Summary written: $summaryPath"
        return $true
    }
    catch {
        Write-Error "Failed to write summary JSON: $_"
        return $false
    }
}

function Write-ProvisionLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [string]$ProvisionLog)

    if ([string]::IsNullOrWhiteSpace($ProvisionLog)) { return }

    $provisionPath = Join-Path $script:OutputDir $script:ProvisionLogFile
    try {
        Set-Content -Path $provisionPath -Value $ProvisionLog -Encoding UTF8 -Force
        Write-Verbose "[albt] Provision log written: $provisionPath"
    }
    catch {
        Write-Verbose "[albt] Failed to write provision log: $_"
    }
}

function Get-ExitCodeForCategory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$Category)

    if ($Category -eq 'success') { return 0 }
    if ($Category -eq 'missing-tool') { return 6 }
    return 1
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Verbose '[albt] Test Overlay Provision Harness initialized'

if ($env:VERBOSE -eq '1') {
    $VerbosePreference = 'Continue'
}

$script:ErrorCategory = 'success'

if (-not (Test-Path $script:OutputDir)) {
    New-Item -ItemType Directory -Path $script:OutputDir -Force | Out-Null
}

Assert-DockerAvailable

if ($PSVersionTable.Platform -ne 'Win32NT') {
    Write-Error 'This harness runs only on Windows hosts for Windows container testing.'
    $script:ErrorCategory = 'missing-tool'
    exit 6
}

$startTime = Get-Date

try {
    $transcriptPath = Start-TestTranscript
    $script:TranscriptPath = $transcriptPath

    Write-Log '[albt] === Overlay Provision Test Harness Started ==='
    Write-Log "[albt] Output directory: $($script:OutputDir)"
    Write-Log "[albt] Transcript: $transcriptPath"

    $errorSummary = $null

    Write-Log '[albt] === Base Image Resolution Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'image-resolution'

    $image = Resolve-BaseImage
    Write-Log "[albt] Base Image: $image"

    Invoke-TimedPhaseStop -PhaseName 'image-resolution'

    Write-Log '[albt] === Container Provision Test Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'container-test'

    $containerId = $null
    $exitCode = 1
    $containerOutput = $null
    $containerProvisionLog = $null

    $containerSuccess = Invoke-ContainerProvisionTest -Image $image `
        -ContainerId ([ref]$containerId) `
        -ExitCode ([ref]$exitCode) `
        -ContainerOutput ([ref]$containerOutput) `
        -ProvisionLog ([ref]$containerProvisionLog)

    Invoke-TimedPhaseStop -PhaseName 'container-test'

    if (-not $containerSuccess) {
        $errorSummary = 'Container execution failed'
        throw "Container execution failed"
    }

    Write-Verbose "[albt] Container exit code: $exitCode"

    if ($exitCode -ne 0) {
        $errorSummary = "Provision test failed with exit code $exitCode"
        $script:ErrorCategory = 'general-error'
    }

    Write-Log '[albt] === Summary Generation Phase ==='
    $endTime = Get-Date

    if ($containerProvisionLog) { Write-ProvisionLog -ProvisionLog $containerProvisionLog }

    $summary = New-TestSummary -Image $image -ContainerId $containerId -StartTime $startTime -EndTime $endTime `
        -ExitCode $exitCode -TranscriptPath $transcriptPath -TimedPhases $script:TimedPhases

    if ($exitCode -ne 0) {
        $summary['errorSummary'] = if ($errorSummary) { $errorSummary } else { "Test failed with exit code $exitCode" }
    } else {
        $script:ErrorCategory = 'success'
    }

    $summarySuccess = Write-TestSummary -Summary $summary
    if (-not $summarySuccess) {
        throw 'Failed to write summary JSON'
    }

    Write-Log '[albt] === Test Complete ==='
    if ($exitCode -eq 0) {
        Write-Log '[albt] Provision test successful'
    } else {
        Write-Log "[albt] Provision test failed with exit code: $exitCode" -Level Error
    }
}
catch {
    Write-Log "[albt] Critical error: $_" -Level Error
    $script:ErrorCategory = 'general-error'
}
finally {
    $finalExitCode = Get-ExitCodeForCategory -Category $script:ErrorCategory
    Write-Log "[albt] === Execution Complete === Exit Code: $finalExitCode"
    Write-Log "[albt] Artifacts available in: $script:OutputDir"
}

exit $finalExitCode
