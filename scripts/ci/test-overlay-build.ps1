#requires -Version 7.2
<#
.SYNOPSIS
    Validates overlay provision scripts within an ephemeral Docker container environment.

.DESCRIPTION
    Provisions a dotnet/sdk container with PowerShell 7, mounts local overlay/ and test fixtures,
    and verifies provision workflows (download-compiler, download-symbols) across 3 scenarios.
    Ensures overlay scripts handle missing dependencies, empty dependencies, and real dependencies correctly.

.PARAMETER Help
    Display this help message and exit.

.PARAMETER ?
    Display this help message and exit (short form).

.EXAMPLE
    pwsh -File scripts/ci/test-overlay-build.ps1 -Verbose

.EXAMPLE
    pwsh -File scripts/ci/test-overlay-build.ps1 -Help

.PARAMETER Environment Variables
    ALBT_TEST_IMAGE            - Docker image reference (default: mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022)
    ALBT_TEST_KEEP_CONTAINER   - Set to '1' to skip auto-remove container for debugging
    VERBOSE                    - Set to enable verbose logging

.OUTPUTS
    Artifacts:
      out/test-overlay/overlay.transcript.txt  - PowerShell transcript
      out/test-overlay/overlay-summary.json    - Execution summary matching overlay-test-summary.schema.json

.EXIT CODES
    0 - Success: All provision scenarios passed
    1 - General Error: Provision failed or validation failed
    6 - MissingTool: Docker not available or overlay mount validation failed

#>

param(
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION & GLOBALS
# ============================================================================

$script:DefaultImage = 'mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022'
$script:OutputDir = 'out/test-overlay'
$script:TranscriptFile = 'overlay.transcript.txt'
$script:SummaryFile = 'overlay-summary.json'
$script:TranscriptPath = $null

$script:ErrorCategory = 'success'

# Timed sections tracking
$script:TimedPhases = @{}

# ============================================================================
# SECTION: Help Display
# ============================================================================

if ($Help -or ($args -contains '-?')) {
    Write-Host @"
SYNOPSIS
    Validates overlay provision scripts within an ephemeral Docker container environment.

DESCRIPTION
    Provisions a dotnet/sdk container with PowerShell 7, mounts local overlay/ and test fixtures,
    and verifies provision workflows (download-compiler, download-symbols) across 3 scenarios.
    Ensures overlay scripts handle missing dependencies, empty dependencies, and real dependencies correctly.

USAGE
    pwsh -File scripts/ci/test-overlay-build.ps1 [OPTIONS]

OPTIONS
    -Help, -?              Display this help message and exit.

ENVIRONMENT VARIABLES
    ALBT_TEST_IMAGE                 - Docker image reference (default: mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022)
    ALBT_TEST_KEEP_CONTAINER        - Set to '1' to skip auto-remove container for debugging
    VERBOSE                         - Set to enable verbose logging

EXAMPLES
    # Run overlay provision tests
    pwsh -File scripts/ci/test-overlay-build.ps1 -Verbose

    # Debug mode: preserve container for inspection
    `$env:ALBT_TEST_KEEP_CONTAINER = '1'
    pwsh -File scripts/ci/test-overlay-build.ps1

EXIT CODES
    0 - Success: All provision scenarios passed
    1 - General Error: Provision failed or validation failed
    6 - MissingTool: Docker not available or overlay mount validation failed

ARTIFACTS
    out/test-overlay/overlay.transcript.txt  - PowerShell transcript
    out/test-overlay/overlay-summary.json    - Execution summary (schema-aligned)

SCOPE
    Tests ONLY overlay provision scripts (download-compiler.ps1, download-symbols.ps1).
    Does NOT test bootstrap installer functionality.
    For installer testing, see test-bootstrap-install.ps1.

"@
    exit 0
}

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

# ============================================================================
# SECTION: Timing
# ============================================================================

function Invoke-TimedPhaseStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PhaseName
    )
    $script:TimedPhases[$PhaseName] = @{
        'start' = Get-Date
        'end'   = $null
    }
    Write-Verbose "[albt] Phase started: $PhaseName"
}

function Invoke-TimedPhaseStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PhaseName
    )
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

function Resolve-ContainerImage {
    [CmdletBinding()]
    param()

    $image = $env:ALBT_TEST_IMAGE
    if ([string]::IsNullOrWhiteSpace($image)) {
        $image = $script:DefaultImage
    }
    Write-Verbose "[albt] Using container image: $image"
    return $image
}

function Get-ImageDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image
    )

    try {
        $inspectOutput = & docker inspect $Image 2>&1
        if ($LASTEXITCODE -eq 0) {
            $imageData = ConvertFrom-Json -InputObject $inspectOutput
            if ($imageData[0].RepoDigests -and $imageData[0].RepoDigests.Count -gt 0) {
                $digest = $imageData[0].RepoDigests[0] -replace '.*@', ''
                $digest = $digest.Substring(0, [Math]::Min(16, $digest.Length))
                return $digest
            }
            $imageId = $imageData[0].Id -replace 'sha256:', ''
            return $imageId.Substring(0, [Math]::Min(16, $imageId.Length))
        }
    }
    catch {
        Write-Verbose "[albt] Failed to get image digest: $_"
    }
    return $null
}

function Invoke-OverlayContainerTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [ref]$ImagePullSeconds,
        [ref]$ContainerCreateSeconds,
        [ref]$ContainerId,
        [ref]$ExitCode,
        [ref]$ImageDigest,
        [ref]$ContainerOutput
    )

    $randomSuffix = -join ((0..9) + ('a'..'f') | Get-Random -Count 8)
    $containerName = "albt-overlay-test-$randomSuffix"

    Write-Log "[albt] Starting overlay container test: $containerName"
    Write-Log "Container name: $containerName"
    Write-Log "Image: $Image"

    # Pull image
    $pullStart = Get-Date
    Write-Log "[albt] Pulling Docker image..."
    try {
        docker pull $Image 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Image pull failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Log "Image pull failed: $_" -Level Error
        $script:ErrorCategory = 'network'
        return $false
    }
    $pullEnd = Get-Date
    $ImagePullSeconds.Value = [int]($pullEnd - $pullStart).TotalSeconds

    $ImageDigest.Value = Get-ImageDigest -Image $Image
    Write-Log "[albt] Image pull completed in $($ImagePullSeconds.Value) seconds"

    # Prepare paths
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $overlayPath = Join-Path $repoRoot 'overlay'
    $fixturesPath = Join-Path $repoRoot 'tests\fixtures\overlay-provision'
    $ciScriptsPath = $PSScriptRoot
    $bootstrapPath = Join-Path $repoRoot 'bootstrap'

    if (-not (Test-Path $overlayPath)) {
        throw "overlay directory not found at $overlayPath"
    }
    if (-not (Test-Path $fixturesPath)) {
        throw "fixtures directory not found at $fixturesPath"
    }
    if (-not (Test-Path (Join-Path $ciScriptsPath 'overlay-test-template.ps1'))) {
        throw "overlay-test-template.ps1 not found in $ciScriptsPath"
    }
    if (-not (Test-Path $bootstrapPath)) {
        throw "bootstrap directory not found at $bootstrapPath"
    }
    if (-not (Test-Path (Join-Path $bootstrapPath 'setup-infrastructure.ps1'))) {
        throw "setup-infrastructure.ps1 not found in $bootstrapPath"
    }

    Write-Log "[albt] Overlay path: $overlayPath"
    Write-Log "[albt] Fixtures path: $fixturesPath"
    Write-Log "[albt] CI scripts path: $ciScriptsPath"
    Write-Log "[albt] Bootstrap path: $bootstrapPath"

    # Run container
    $createStart = Get-Date
    Write-Log "[albt] Creating and running container..."

    try {
        $runArgs = @(
            'run'
            '--name', $containerName
        )

        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            $runArgs += '--rm'
        }

        # Mount volumes
        $runArgs += @(
            '-v', "${overlayPath}:C:\overlay"
            '-v', "${fixturesPath}:C:\fixtures"
            '-v', "${ciScriptsPath}:C:\test"
            '-v', "${bootstrapPath}:C:\bootstrap"
            $Image
            'pwsh.exe'
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File'
            'C:\test\overlay-test-template.ps1'
        )

        Write-Log "[albt] Executing: docker run ... pwsh -File overlay-test-template.ps1"

        # Run the container and capture output for parsing
        $outputLines = New-Object System.Collections.ArrayList
        $dockerExitCode = 0

        & docker @runArgs 2>&1 | ForEach-Object {
            Write-Host $_  # Stream to console in real-time
            [void]$outputLines.Add($_)
        }
        $dockerExitCode = $LASTEXITCODE

        $ExitCode.Value = $dockerExitCode
        $ContainerOutput.Value = $outputLines.ToArray()
        Write-Log "[albt] Container completed with exit code: $($ExitCode.Value)"
    }
    catch {
        Write-Log "Failed to run container: $_" -Level Error
        $script:ErrorCategory = 'integration'
        return $false
    }
    finally {
        $createEnd = Get-Date
        $ContainerCreateSeconds.Value = [int]($createEnd - $createStart).TotalSeconds

        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            Remove-ContainerSafely -ContainerName $containerName
            Write-Log "[albt] Container removed"
        }
        else {
            Write-Log "[albt] Keeping container for debugging: $containerName"
        }

        Write-Log "[albt] Container execution completed in $($ContainerCreateSeconds.Value) seconds"
    }

    $ContainerId.Value = $containerName
    return $true
}

function Remove-ContainerSafely {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName
    )

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
# SECTION: Overlay Mount Validation
# ============================================================================

function Test-OverlayMountValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$ContainerOutput
    )

    # Look for validation markers from overlay-test-template.ps1
    # Success pattern: "Overlay Path: C:\overlay"
    $foundOverlay = $false
    $foundFixtures = $false

    foreach ($line in $ContainerOutput) {
        if ($line -match 'Overlay Path:\s*C:\\overlay') {
            $foundOverlay = $true
        }
        if ($line -match 'Fixtures Path:\s*C:\\fixtures') {
            $foundFixtures = $true
        }
    }

    if (-not $foundOverlay) {
        Write-Log "Overlay mount validation failed: C:\overlay not accessible" -Level Error
        return $false
    }

    if (-not $foundFixtures) {
        Write-Log "Fixtures mount validation failed: C:\fixtures not accessible" -Level Error
        return $false
    }

    Write-Log "Overlay mount validation: PASSED"
    return $true
}

# ============================================================================
# SECTION: Transcript
# ============================================================================

function Start-OverlayTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $transcriptPath = Join-Path $script:OutputDir $script:TranscriptFile
    Write-Host "[albt] Transcript will be written to: $transcriptPath"

    $header = @"
================================================================================
PowerShell Transcript Start - Overlay Provision Tests
StartTime: $(Get-Date -Format 'o')
StartPath: $(Get-Location)
Version: $($PSVersionTable.PSVersion)
================================================================================
"@

    $header | Out-File -Path $transcriptPath -Encoding UTF8 -Force
    return $transcriptPath
}

function Stop-OverlayTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Write-Host '[albt] Transcript generation complete'
}

function Invoke-TranscriptAppendContainerOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$TranscriptPath,
        [Parameter(Mandatory = $true)] [object[]]$ContainerOutput,
        [Parameter(Mandatory = $true)] [int]$ExitCode
    )

    if ($ExitCode -eq 0) {
        return
    }

    if (-not $ContainerOutput -or $ContainerOutput.Count -eq 0) {
        return
    }

    try {
        $tail = @()
        $tail += "`n=================== CONTAINER OUTPUT TAIL ==================="
        $tail += "[Exit Code: $ExitCode]"

        if ($ContainerOutput.Count -le 50) {
            $tail += $ContainerOutput
        }
        else {
            $tail += $ContainerOutput[($ContainerOutput.Count - 50)..($ContainerOutput.Count - 1)]
        }
        $tail += "=================== END CONTAINER OUTPUT ==================="

        Add-Content -Path $TranscriptPath -Value ($tail -join "`n") -Encoding UTF8
        Write-Verbose "[albt] Container output appended to transcript"
    }
    catch {
        Write-Verbose "[albt] Failed to append container output to transcript: $_"
    }
}

function Invoke-TranscriptSizeProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$TranscriptPath
    )

    if (-not (Test-Path $TranscriptPath)) {
        return
    }

    try {
        $file = Get-Item -Path $TranscriptPath -ErrorAction Stop
        $maxSize = 5MB

        if ($file.Length -gt $maxSize) {
            Write-Verbose "[albt] Transcript exceeds 5MB ($($file.Length / 1MB)MB); truncating..."

            $content = Get-Content -Path $TranscriptPath -Raw -ErrorAction Stop
            $truncated = "[TRANSCRIPT TRUNCATED - Original size: $('{0:N2}' -f ($file.Length / 1MB)) MB]`n`n"
            $truncated += $content.Substring([Math]::Max(0, $content.Length - (4MB)))
            $truncated += "`n`n[END OF TRUNCATED TRANSCRIPT]"

            Set-Content -Path $TranscriptPath -Value $truncated -Encoding UTF8 -Force
            Write-Verbose "[albt] Transcript truncated to approximately 4MB"
        }
    }
    catch {
        Write-Verbose "[albt] Failed to check/truncate transcript: $_"
    }
}

# ============================================================================
# SECTION: Summary Generation
# ============================================================================

function New-OverlayTestSummary {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [Parameter(Mandatory = $false)] [string]$ContainerId,
        [Parameter(Mandatory = $true)] [DateTime]$StartTime,
        [Parameter(Mandatory = $true)] [DateTime]$EndTime,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $true)] [string]$PSVersion,
        [Parameter(Mandatory = $false)] [string]$DotnetSdkVersion = '8.0',
        [Parameter(Mandatory = $false)] [string]$ErrorSummary = '',
        [Parameter(Mandatory = $false)] [string]$TranscriptPath = '',
        [Parameter(Mandatory = $false)] [string]$ImageDigest = '',
        [Parameter(Mandatory = $false)] [hashtable]$TimedPhases = @{},
        [Parameter(Mandatory = $false)] [array]$ScenarioResults = @()
    )

    $durationSeconds = [int]($EndTime - $StartTime).TotalSeconds
    $success = ($ExitCode -eq 0)

    $summary = @{
        image                 = $Image
        startTime             = $StartTime.ToUniversalTime().ToString('o')
        endTime               = $EndTime.ToUniversalTime().ToString('o')
        durationSeconds       = $durationSeconds
        exitCode              = $ExitCode
        success               = $success
        psVersion             = $PSVersion
        dotnetSdkVersion      = $DotnetSdkVersion
        overlaySource         = 'local'
        testedScripts         = @('download-compiler.ps1', 'download-symbols.ps1')
        scenarioResults       = $ScenarioResults
        cacheLocations        = @{
            toolCache   = '~/.bc-tool-cache'
            symbolCache = '~/.bc-symbol-cache'
        }
    }

    if ($ContainerId) {
        $summary['containerId'] = $ContainerId
    }

    if ($ImageDigest) {
        $summary['imageDigest'] = $ImageDigest
    }

    if ($ErrorSummary) {
        $summary['errorSummary'] = $ErrorSummary
    }

    if ($TimedPhases.Count -gt 0) {
        $phases = @{}
        foreach ($phaseName in $TimedPhases.Keys) {
            $phase = $TimedPhases[$phaseName]
            if ($phase['end']) {
                $phaseDuration = [int]($phase['end'] - $phase['start']).TotalSeconds
                $phases[$phaseName] = @{
                    'durationSeconds' = $phaseDuration
                }
            }
        }
        if ($phases.Count -gt 0) {
            $summary['phases'] = $phases
        }
    }

    if ($TranscriptPath) {
        $summary['transcriptPath'] = $TranscriptPath
    }

    return $summary
}

function Write-OverlayTestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [hashtable]$Summary
    )

    $summaryPath = Join-Path $script:OutputDir $script:SummaryFile

    $requiredFields = @('image', 'startTime', 'endTime', 'durationSeconds', 'exitCode', 'success', 'psVersion', 'overlaySource', 'scenarioResults')
    $missing = @()
    foreach ($field in $requiredFields) {
        if (-not $Summary.ContainsKey($field)) {
            $missing += $field
        }
    }

    if ($missing.Count -gt 0) {
        Write-Error "Summary missing required fields: $($missing -join ', ')"
        return $false
    }

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

# ============================================================================
# SECTION: Output Parsing
# ============================================================================

function Extract-PSVersionFromOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    if (-not $Output) {
        return $null
    }

    $versionPattern = '(\d+\.\d+\.\d+)'
    foreach ($line in $Output) {
        if ($line -match 'PowerShell Version:\s*(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
        if ($line -match $versionPattern -and $line -match '^7\.') {
            return $Matches[1]
        }
    }

    return $null
}

function Extract-ScenarioResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    $scenarios = @()

    # Parse scenario results from container output
    # Expected patterns:
    # "Scenario 1: PASSED" or "Scenario 1: FAILED"
    # Validation steps: "✓ step" or "✗ step"

    $currentScenario = $null
    $validationSteps = @()

    foreach ($line in $Output) {
        # Scenario header: "[SCEN] Setting up Scenario N: <name>"
        if ($line -match '\[SCEN\]\s+Setting up Scenario (\d+):\s*(.+)') {
            if ($currentScenario) {
                $scenarios += $currentScenario
            }
            $currentScenario = @{
                scenarioId = [int]$Matches[1]
                name = $Matches[2].Trim()
                passed = $false
                validationDetails = @()
            }
            $validationSteps = @()
        }

        # Validation steps: "✓ <step>" or "✗ <step>"
        if ($line -match '✓\s+(.+)') {
            $validationSteps += @{ step = $Matches[1].Trim(); passed = $true }
        }
        if ($line -match '✗\s+(.+)') {
            $validationSteps += @{ step = $Matches[1].Trim(); passed = $false }
        }

        # Scenario result: "Scenario N: PASSED" or "Scenario N: FAILED"
        if ($line -match 'Scenario\s+(\d+):\s+(PASSED|FAILED)') {
            $scenarioId = [int]$Matches[1]
            $passed = $Matches[2] -eq 'PASSED'

            if ($currentScenario -and $currentScenario.scenarioId -eq $scenarioId) {
                $currentScenario.passed = $passed
                $currentScenario.validationDetails = $validationSteps
                $scenarios += $currentScenario
                $currentScenario = $null
                $validationSteps = @()
            }
        }
    }

    # Add last scenario if not closed
    if ($currentScenario) {
        $scenarios += $currentScenario
    }

    return $scenarios
}

# ============================================================================
# SECTION: Error Handling
# ============================================================================

function Get-ExitCodeForCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Category
    )

    if ($Category -eq 'success') { return 0 }
    if ($Category -eq 'missing-tool') { return 6 }
    return 1
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Verbose '[albt] Test Overlay Build Harness initialized'

if ($env:VERBOSE -eq '1') {
    $VerbosePreference = 'Continue'
}

# Safety check for non-Windows host
if ($PSVersionTable.Platform -ne 'Win32NT') {
    Write-Error 'This harness runs only on Windows hosts for Windows container testing.'
    $script:ErrorCategory = 'missing-tool'
    exit 6
}

if (-not (Test-Path $script:OutputDir)) {
    New-Item -ItemType Directory -Path $script:OutputDir -Force | Out-Null
}

Assert-DockerAvailable

$startTime = Get-Date

try {
    $transcriptPath = Start-OverlayTranscript
    $script:TranscriptPath = $transcriptPath

    Write-Log '[albt] === Overlay Provision Test Harness Started ==='
    Write-Log "[albt] Output directory: $($script:OutputDir)"
    Write-Log "[albt] Transcript: $transcriptPath"

    Write-Log '[albt] === Container Provisioning Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'container-provisioning'

    $image = Resolve-ContainerImage

    Write-Log '[albt] === Configuration Summary ==='
    Write-Log "[albt] Container Image:  $image"
    Write-Log "[albt] Overlay Source:   local"
    Write-Log '[albt] === End Configuration ==='

    $imagePullSeconds = 0
    $containerCreateSeconds = 0
    $containerId = $null
    $exitCode = 1
    $containerOutput = $null
    $imageDigest = $null

    $containerSuccess = Invoke-OverlayContainerTest -Image $image `
        -ImagePullSeconds ([ref]$imagePullSeconds) `
        -ContainerCreateSeconds ([ref]$containerCreateSeconds) `
        -ContainerId ([ref]$containerId) `
        -ExitCode ([ref]$exitCode) `
        -ImageDigest ([ref]$imageDigest) `
        -ContainerOutput ([ref]$containerOutput)

    Invoke-TimedPhaseStop -PhaseName 'container-provisioning'

    if (-not $containerSuccess) {
        throw "Container execution failed"
    }

    Write-Verbose "[albt] Container exit code: $exitCode"

    # Validate overlay mount
    $mountValid = Test-OverlayMountValidation -ContainerOutput $containerOutput
    if (-not $mountValid) {
        Write-Log "Overlay mount validation failed" -Level Error
        $script:ErrorCategory = 'missing-tool'
        $exitCode = 6
    }

    # Extract PowerShell version
    $psVersion = Extract-PSVersionFromOutput -Output $containerOutput
    if (-not $psVersion) {
        Write-Verbose '[albt] PowerShell version not captured; using fallback'
        $psVersion = '7.2.0'
    }

    # Extract scenario results
    $scenarioResults = Extract-ScenarioResults -Output $containerOutput
    Write-Log "[albt] Extracted $($scenarioResults.Count) scenario results"

    Write-Log '[albt] === Summary Generation Phase ==='
    $endTime = Get-Date

    if ($exitCode -ne 0 -and $containerOutput) {
        Invoke-TranscriptAppendContainerOutput -TranscriptPath $transcriptPath -ContainerOutput $containerOutput -ExitCode $exitCode
    }

    $errorSummary = $null
    if ($exitCode -ne 0) {
        $failedScenarios = $scenarioResults | Where-Object { -not $_.passed }
        if ($failedScenarios.Count -gt 0) {
            $failedNames = ($failedScenarios | ForEach-Object { "Scenario $($_.scenarioId)" }) -join ', '
            $errorSummary = "Provision tests failed: $failedNames"
        }
        else {
            $errorSummary = "Provision tests failed with exit code $exitCode"
        }
        $script:ErrorCategory = 'integration'
    }
    else {
        $script:ErrorCategory = 'success'
    }

    $summary = New-OverlayTestSummary -Image $image -ContainerId $containerId -StartTime $startTime -EndTime $endTime `
        -ExitCode $exitCode -PSVersion $psVersion -DotnetSdkVersion '8.0' `
        -TranscriptPath $transcriptPath -ImageDigest $imageDigest -TimedPhases $script:TimedPhases `
        -ScenarioResults $scenarioResults -ErrorSummary $errorSummary

    $summarySuccess = Write-OverlayTestSummary -Summary $summary
    if (-not $summarySuccess) {
        throw 'Failed to write summary JSON'
    }

    Invoke-TranscriptSizeProtection -TranscriptPath $transcriptPath

    Write-Log '[albt] === Overlay Tests Complete ==='
    if ($exitCode -eq 0) {
        Write-Log '[albt] All provision scenarios passed'
    }
    else {
        Write-Log "[albt] Provision tests failed with exit code: $exitCode" -Level Error
    }
}
catch {
    Write-Log "[albt] Critical error: $_" -Level Error
    $script:ErrorCategory = 'integration'
}
finally {
    Stop-OverlayTranscript
    $finalExitCode = Get-ExitCodeForCategory -Category $script:ErrorCategory
    Write-Log "[albt] === Execution Complete === Exit Code: $finalExitCode"
    Write-Log "[albt] Artifacts available in: $script:OutputDir"
}

exit $finalExitCode
